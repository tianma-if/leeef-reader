package server

import (
	"context"
	"crypto/subtle"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"path/filepath"

	"github.com/modelcontextprotocol/go-sdk/mcp"
	_ "modernc.org/sqlite"
)

type Config struct {
	Token        string
	DatabasePath string
}

type Server struct {
	handler http.Handler
	db      *sql.DB
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
		databaseURL := (&url.URL{
			Scheme:   "file",
			Path:     slashPath,
			RawQuery: "mode=ro",
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

	mcpHandler := mcp.NewStreamableHTTPHandler(
		func(request *http.Request) *mcp.Server { return mcpServer },
		&mcp.StreamableHTTPOptions{JSONResponse: true},
	)
	return &Server{handler: authenticate(config.Token, mcpHandler), db: db}, nil
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
