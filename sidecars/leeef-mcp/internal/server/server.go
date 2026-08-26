package server

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"path/filepath"
	"sync"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	_ "modernc.org/sqlite"
)

type Config struct {
	Token        string
	DatabasePath string
	DeviceID     string
	Writable     bool
}

type Server struct {
	handler http.Handler
	db      *sql.DB
	plans   *writePlanStore
	config  Config
}

type HealthInput struct{}

type HealthOutput struct {
	Status            string `json:"status" jsonschema:"Current sidecar status"`
	DatabaseConnected bool   `json:"databaseConnected" jsonschema:"Whether the Leeef database is readable"`
}

type LibraryStatsInput struct{}

type LibraryStatsOutput struct {
	Books          int `json:"books"`
	Excerpts       int `json:"excerpts"`
	Bookmarks      int `json:"bookmarks"`
	PendingSyncOps int `json:"pendingSyncOperations"`
}

type BookSummary struct {
	ID        string  `json:"id"`
	Title     string  `json:"title"`
	Author    *string `json:"author,omitempty"`
	MediaType string  `json:"mediaType"`
}

type ListBooksInput struct{}

type ListBooksOutput struct {
	Books []BookSummary `json:"books"`
}

type PlanCreateExcerptInput struct {
	BookID  string  `json:"bookId" jsonschema:"Stable ID of the source book"`
	Locator string  `json:"locator" jsonschema:"EPUB CFI for the selected text"`
	Quote   string  `json:"quote" jsonschema:"Exact selected text"`
	Note    *string `json:"note,omitempty" jsonschema:"Optional user note"`
	Color   string  `json:"color,omitempty" jsonschema:"Highlight color"`
}

type PlanWriteOutput struct {
	PlanID    string    `json:"planId"`
	Summary   string    `json:"summary"`
	ExpiresAt time.Time `json:"expiresAt"`
}

type ConfirmWriteInput struct {
	PlanID string `json:"planId"`
}

type ConfirmWriteOutput struct {
	PlanID            string `json:"planId"`
	ConfirmationToken string `json:"confirmationToken"`
}

type ApplyWriteInput struct {
	PlanID            string `json:"planId"`
	ConfirmationToken string `json:"confirmationToken"`
}

type ApplyWriteOutput struct {
	EntityID    string `json:"entityId"`
	OperationID string `json:"operationId"`
	Applied     bool   `json:"applied"`
}

type excerptWritePlan struct {
	Input             PlanCreateExcerptInput
	Action            string
	Payload           json.RawMessage
	EntityID          string
	OperationID       string
	Applied           bool
	ExpiresAt         time.Time
	ConfirmationToken string
}

type writePlanStore struct {
	mu    sync.Mutex
	plans map[string]excerptWritePlan
}

func New(config Config) (*Server, error) {
	if config.Token == "" {
		return nil, errors.New("sidecar token must not be empty")
	}

	var db *sql.DB
	if config.DatabasePath != "" {
		absolutePath, err := filepath.Abs(config.DatabasePath)
		if err != nil {
			return nil, fmt.Errorf("resolve database path: %w", err)
		}
		slashPath := filepath.ToSlash(absolutePath)
		if filepath.VolumeName(absolutePath) != "" {
			slashPath = "/" + slashPath
		}
		mode := "ro"
		if config.Writable {
			mode = "rw"
		}
		databaseURL := (&url.URL{
			Scheme:   "file",
			Path:     slashPath,
			RawQuery: "mode=" + mode,
		}).String()
		db, err = sql.Open("sqlite", databaseURL)
		if err != nil {
			return nil, fmt.Errorf("open database: %w", err)
		}
		if err := db.Ping(); err != nil {
			db.Close()
			return nil, fmt.Errorf("ping database: %w", err)
		}
	}

	mcpServer := mcp.NewServer(
		&mcp.Implementation{Name: "leeef-mcp", Version: "0.1.0"},
		nil,
	)
	mcp.AddTool(mcpServer, &mcp.Tool{
		Name:        "health",
		Description: "Check whether the Leeef MCP sidecar and database bridge are healthy.",
	}, func(ctx context.Context, request *mcp.CallToolRequest, input HealthInput) (*mcp.CallToolResult, HealthOutput, error) {
		connected := db != nil && db.PingContext(ctx) == nil
		return nil, HealthOutput{Status: "ok", DatabaseConnected: connected}, nil
	})
	mcp.AddTool(mcpServer, &mcp.Tool{
		Name:        "library_stats",
		Description: "Return non-deleted library counts and pending sync operation count.",
	}, func(ctx context.Context, request *mcp.CallToolRequest, input LibraryStatsInput) (*mcp.CallToolResult, LibraryStatsOutput, error) {
		if db == nil {
			return nil, LibraryStatsOutput{}, errors.New("database path was not configured")
		}
		stats, err := readLibraryStats(ctx, db)
		return nil, stats, err
	})
	mcp.AddTool(mcpServer, &mcp.Tool{
		Name:        "list_books",
		Description: "List the visible books in the Leeef library.",
	}, func(ctx context.Context, request *mcp.CallToolRequest, input ListBooksInput) (*mcp.CallToolResult, ListBooksOutput, error) {
		if db == nil {
			return nil, ListBooksOutput{}, errors.New("database path was not configured")
		}
		books, err := readBooks(ctx, db)
		return nil, ListBooksOutput{Books: books}, err
	})
	registerReadCapabilities(mcpServer, db)

	plans := &writePlanStore{plans: make(map[string]excerptWritePlan)}
	registerManagementTools(mcpServer, db, plans, config)
	mcp.AddTool(mcpServer, &mcp.Tool{
		Name:        "plan_create_excerpt",
		Description: "Prepare an excerpt write without changing data. The returned plan must be explicitly confirmed and applied.",
	}, func(ctx context.Context, request *mcp.CallToolRequest, input PlanCreateExcerptInput) (*mcp.CallToolResult, PlanWriteOutput, error) {
		if !config.Writable || db == nil {
			return nil, PlanWriteOutput{}, errors.New("MCP writes are disabled")
		}
		if input.BookID == "" || input.Locator == "" || input.Quote == "" {
			return nil, PlanWriteOutput{}, errors.New("bookId, locator, and quote are required")
		}
		var exists int
		if err := db.QueryRowContext(ctx, "SELECT count(*) FROM books WHERE id = ? AND is_deleted = 0", input.BookID).Scan(&exists); err != nil {
			return nil, PlanWriteOutput{}, fmt.Errorf("validate book: %w", err)
		}
		if exists != 1 {
			return nil, PlanWriteOutput{}, errors.New("book does not exist")
		}
		if input.Color == "" {
			input.Color = "yellow"
		}
		planID, err := randomID("plan")
		if err != nil {
			return nil, PlanWriteOutput{}, err
		}
		expiresAt := time.Now().UTC().Add(5 * time.Minute)
		plans.mu.Lock()
		plans.plans[planID] = excerptWritePlan{Input: input, ExpiresAt: expiresAt}
		plans.mu.Unlock()
		return nil, PlanWriteOutput{
			PlanID:    planID,
			Summary:   fmt.Sprintf("Create excerpt in book %s: %.80s", input.BookID, input.Quote),
			ExpiresAt: expiresAt,
		}, nil
	})
	mcp.AddTool(mcpServer, &mcp.Tool{
		Name:        "confirm_write",
		Description: "Confirm a previously reviewed write plan and receive a one-time apply token.",
	}, func(ctx context.Context, request *mcp.CallToolRequest, input ConfirmWriteInput) (*mcp.CallToolResult, ConfirmWriteOutput, error) {
		plans.mu.Lock()
		defer plans.mu.Unlock()
		plan, ok := plans.plans[input.PlanID]
		if !ok || time.Now().UTC().After(plan.ExpiresAt) {
			delete(plans.plans, input.PlanID)
			return nil, ConfirmWriteOutput{}, errors.New("write plan is missing or expired")
		}
		token, err := randomID("confirm")
		if err != nil {
			return nil, ConfirmWriteOutput{}, err
		}
		plan.ConfirmationToken = token
		plans.plans[input.PlanID] = plan
		return nil, ConfirmWriteOutput{PlanID: input.PlanID, ConfirmationToken: token}, nil
	})
	mcp.AddTool(mcpServer, &mcp.Tool{
		Name:        "apply_write",
		Description: "Apply a confirmed one-time write plan transactionally, including sync operation and audit event.",
	}, func(ctx context.Context, request *mcp.CallToolRequest, input ApplyWriteInput) (*mcp.CallToolResult, ApplyWriteOutput, error) {
		plans.mu.Lock()
		defer plans.mu.Unlock()
		plan, ok := plans.plans[input.PlanID]
		if !ok || time.Now().UTC().After(plan.ExpiresAt) {
			delete(plans.plans, input.PlanID)
			return nil, ApplyWriteOutput{}, errors.New("write plan is missing or expired")
		}
		if plan.ConfirmationToken == "" || subtle.ConstantTimeCompare([]byte(plan.ConfirmationToken), []byte(input.ConfirmationToken)) != 1 {
			return nil, ApplyWriteOutput{}, errors.New("write plan was not confirmed")
		}
		if plan.Applied {
			return nil, ApplyWriteOutput{EntityID: plan.EntityID, OperationID: plan.OperationID, Applied: true}, nil
		}
		var entityID, operationID string
		var err error
		if plan.Action == "" {
			entityID, operationID, err = applyExcerptPlan(ctx, db, config.DeviceID, input.PlanID, plan)
		} else {
			entityID, operationID, err = applyManagedPlan(ctx, db, config.DeviceID, input.PlanID, plan)
		}
		if err != nil {
			return nil, ApplyWriteOutput{}, err
		}
		plan.Applied = true
		plan.EntityID = entityID
		plan.OperationID = operationID
		plans.plans[input.PlanID] = plan
		return nil, ApplyWriteOutput{EntityID: entityID, OperationID: operationID, Applied: true}, nil
	})

	mcpHandler := mcp.NewStreamableHTTPHandler(
		func(request *http.Request) *mcp.Server { return mcpServer },
		&mcp.StreamableHTTPOptions{JSONResponse: true},
	)
	return &Server{handler: authenticate(config.Token, mcpHandler), db: db, plans: plans, config: config}, nil
}

func (s *Server) ServeHTTP(writer http.ResponseWriter, request *http.Request) {
	s.handler.ServeHTTP(writer, request)
}

func (s *Server) Close() error {
	if s.db == nil {
		return nil
	}
	return s.db.Close()
}

func authenticate(token string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		provided := request.Header.Get("Authorization")
		expected := "Bearer " + token
		if len(provided) != len(expected) || subtle.ConstantTimeCompare([]byte(provided), []byte(expected)) != 1 {
			writer.Header().Set("WWW-Authenticate", "Bearer")
			http.Error(writer, "Unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(writer, request)
	})
}

func readLibraryStats(ctx context.Context, db *sql.DB) (LibraryStatsOutput, error) {
	queries := []struct {
		query  string
		target *int
	}{
		{"SELECT count(*) FROM books WHERE is_deleted = 0", nil},
		{"SELECT count(*) FROM excerpts WHERE is_deleted = 0", nil},
		{"SELECT count(*) FROM bookmarks WHERE is_deleted = 0", nil},
		{"SELECT count(*) FROM sync_operations WHERE applied_at IS NULL", nil},
	}
	var stats LibraryStatsOutput
	queries[0].target = &stats.Books
	queries[1].target = &stats.Excerpts
	queries[2].target = &stats.Bookmarks
	queries[3].target = &stats.PendingSyncOps
	for _, item := range queries {
		if err := db.QueryRowContext(ctx, item.query).Scan(item.target); err != nil {
			return LibraryStatsOutput{}, fmt.Errorf("query library stats: %w", err)
		}
	}
	return stats, nil
}

func readBooks(ctx context.Context, db *sql.DB) ([]BookSummary, error) {
	rows, err := db.QueryContext(ctx, "SELECT id, title, author, media_type FROM books WHERE is_deleted = 0 ORDER BY updated_at DESC")
	if err != nil {
		return nil, fmt.Errorf("query books: %w", err)
	}
	defer rows.Close()
	books := make([]BookSummary, 0)
	for rows.Next() {
		var book BookSummary
		if err := rows.Scan(&book.ID, &book.Title, &book.Author, &book.MediaType); err != nil {
			return nil, fmt.Errorf("scan book: %w", err)
		}
		books = append(books, book)
	}
	return books, rows.Err()
}

func applyExcerptPlan(ctx context.Context, db *sql.DB, deviceID, planID string, plan excerptWritePlan) (string, string, error) {
	if deviceID == "" {
		deviceID = "mcp-sidecar"
	}
	entityID, err := randomID("excerpt")
	if err != nil {
		return "", "", err
	}
	operationID, err := randomID("op")
	if err != nil {
		return "", "", err
	}
	auditID, err := randomID("audit")
	if err != nil {
		return "", "", err
	}
	now := time.Now().UTC()
	nowValue := now.Format(time.RFC3339Nano)
	payload := map[string]any{
		"id": entityID, "bookId": plan.Input.BookID, "locator": plan.Input.Locator,
		"quote": plan.Input.Quote, "note": plan.Input.Note, "color": plan.Input.Color,
	}
	payloadJSON, err := json.Marshal(payload)
	if err != nil {
		return "", "", err
	}
	auditParameters, err := json.Marshal(map[string]any{"planId": planID, "payload": payload})
	if err != nil {
		return "", "", err
	}
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return "", "", fmt.Errorf("begin excerpt write: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `INSERT INTO excerpts
		(id, book_id, locator, quote, note, color, is_deleted, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)`, entityID, plan.Input.BookID, plan.Input.Locator,
		plan.Input.Quote, plan.Input.Note, plan.Input.Color, nowValue, nowValue); err != nil {
		return "", "", fmt.Errorf("insert excerpt: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO sync_operations
		(operation_id, device_id, entity_type, entity_id, kind, payload_json, occurred_at, applied_at)
		VALUES (?, ?, 'excerpt', ?, 'upsert', ?, ?, NULL)`, operationID, deviceID, entityID, string(payloadJSON), nowValue); err != nil {
		return "", "", fmt.Errorf("append sync operation: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO audit_events
		(id, caller, action, parameters_json, result, occurred_at)
		VALUES (?, 'mcp', 'create_excerpt', ?, 'applied', ?)`, auditID, string(auditParameters), nowValue); err != nil {
		return "", "", fmt.Errorf("append audit event: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return "", "", fmt.Errorf("commit excerpt write: %w", err)
	}
	return entityID, operationID, nil
}

func randomID(prefix string) (string, error) {
	bytes := make([]byte, 16)
	if _, err := rand.Read(bytes); err != nil {
		return "", fmt.Errorf("generate ID: %w", err)
	}
	return prefix + "-" + hex.EncodeToString(bytes), nil
}
