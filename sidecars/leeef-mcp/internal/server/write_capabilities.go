package server

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type UpdateBookMetadataInput struct {
	BookID      string   `json:"bookId"`
	Title       string   `json:"title"`
	Author      *string  `json:"author,omitempty"`
	Description *string  `json:"description,omitempty"`
	Rating      *float64 `json:"rating,omitempty"`
}

type MoveBookInput struct {
	BookID      string `json:"bookId"`
	BookshelfID string `json:"bookshelfId"`
	SortOrder   int    `json:"sortOrder"`
}

type EntityIDInput struct {
	ID string `json:"id" jsonschema:"Stable entity ID"`
}

type CreateExcerptInput struct {
	BookID  string  `json:"bookId"`
	Locator string  `json:"locator"`
	Quote   string  `json:"quote"`
	Note    *string `json:"note,omitempty"`
	Color   string  `json:"color,omitempty"`
}

type UpdateExcerptInput struct {
	ExcerptID string  `json:"excerptId"`
	Note      *string `json:"note,omitempty"`
	Color     string  `json:"color"`
}

type CreateBookmarkInput struct {
	BookID  string  `json:"bookId"`
	Locator string  `json:"locator"`
	Title   *string `json:"title,omitempty"`
	Note    *string `json:"note,omitempty"`
}

type UpdateBookmarkInput struct {
	BookmarkID string  `json:"bookmarkId"`
	Title      *string `json:"title,omitempty"`
	Note       *string `json:"note,omitempty"`
}

type CreateBookshelfInput struct {
	Name      string  `json:"name"`
	ParentID  *string `json:"parentId,omitempty"`
	SortOrder int     `json:"sortOrder"`
}

type RenameBookshelfInput struct {
	BookshelfID string `json:"bookshelfId"`
	Name        string `json:"name"`
}

type MoveBookshelfInput struct {
	BookshelfID string  `json:"bookshelfId"`
	ParentID    *string `json:"parentId,omitempty"`
	SortOrder   int     `json:"sortOrder"`
}

type BookshelfMembershipInput struct {
	BookshelfID string `json:"bookshelfId"`
	BookID      string `json:"bookId"`
	SortOrder   int    `json:"sortOrder"`
}

type UpdateReadingProgressInput struct {
	BookID       string  `json:"bookId"`
	Locator      string  `json:"locator"`
	Progress     float64 `json:"progress"`
	ChapterTitle *string `json:"chapterTitle,omitempty"`
	Page         *int    `json:"page,omitempty"`
}

func registerManagementTools(server *mcp.Server, db *sql.DB, plans *writePlanStore, config Config) {
	addPlanTool(server, "update_book_metadata", "Plan a title, author, description, or rating update.", plans, config, db,
		func(input UpdateBookMetadataInput) (string, string, any, error) {
			if input.BookID == "" || strings.TrimSpace(input.Title) == "" {
				return "", "", nil, errors.New("bookId and title are required")
			}
			if input.Rating != nil && (*input.Rating < 0 || *input.Rating > 5) {
				return "", "", nil, errors.New("rating must be between 0 and 5")
			}
			return "update_book_metadata", input.BookID, input, nil
		})
	addPlanTool(server, "move_book", "Plan moving a book into a bookshelf.", plans, config, db,
		func(input MoveBookInput) (string, string, any, error) {
			if input.BookID == "" || input.BookshelfID == "" {
				return "", "", nil, errors.New("bookId and bookshelfId are required")
			}
			return "move_book", input.BookshelfID + "--" + input.BookID, input, nil
		})
	addPlanTool(server, "delete_book", "Plan a soft deletion of a book.", plans, config, db,
		func(input BookIDInput) (string, string, any, error) {
			if input.BookID == "" {
				return "", "", nil, errors.New("bookId is required")
			}
			return "delete_book", input.BookID, input, nil
		})

	addPlanTool(server, "create_excerpt", "Plan creating an excerpt.", plans, config, db,
		func(input CreateExcerptInput) (string, string, any, error) {
			if input.BookID == "" || input.Locator == "" || strings.TrimSpace(input.Quote) == "" {
				return "", "", nil, errors.New("bookId, locator, and quote are required")
			}
			if input.Color == "" {
				input.Color = "yellow"
			}
			return "create_excerpt", "", input, nil
		})
	addPlanTool(server, "update_excerpt", "Plan updating an excerpt note and color.", plans, config, db,
		func(input UpdateExcerptInput) (string, string, any, error) {
			if input.ExcerptID == "" || input.Color == "" {
				return "", "", nil, errors.New("excerptId and color are required")
			}
			return "update_excerpt", input.ExcerptID, input, nil
		})
	addPlanTool(server, "delete_excerpt", "Plan deleting an excerpt.", plans, config, db,
		func(input EntityIDInput) (string, string, any, error) {
			if input.ID == "" {
				return "", "", nil, errors.New("id is required")
			}
			return "delete_excerpt", input.ID, input, nil
		})

	addPlanTool(server, "create_bookmark", "Plan creating a bookmark.", plans, config, db,
		func(input CreateBookmarkInput) (string, string, any, error) {
			if input.BookID == "" || input.Locator == "" {
				return "", "", nil, errors.New("bookId and locator are required")
			}
			return "create_bookmark", "", input, nil
		})
	addPlanTool(server, "update_bookmark", "Plan updating a bookmark.", plans, config, db,
		func(input UpdateBookmarkInput) (string, string, any, error) {
			if input.BookmarkID == "" {
				return "", "", nil, errors.New("bookmarkId is required")
			}
			return "update_bookmark", input.BookmarkID, input, nil
		})
	addPlanTool(server, "delete_bookmark", "Plan deleting a bookmark.", plans, config, db,
		func(input EntityIDInput) (string, string, any, error) {
			if input.ID == "" {
				return "", "", nil, errors.New("id is required")
			}
			return "delete_bookmark", input.ID, input, nil
		})

	addPlanTool(server, "create_bookshelf", "Plan creating a bookshelf.", plans, config, db,
		func(input CreateBookshelfInput) (string, string, any, error) {
			if strings.TrimSpace(input.Name) == "" {
				return "", "", nil, errors.New("name is required")
			}
			return "create_bookshelf", "", input, nil
		})
	addPlanTool(server, "rename_bookshelf", "Plan renaming a bookshelf.", plans, config, db,
		func(input RenameBookshelfInput) (string, string, any, error) {
			if input.BookshelfID == "" || strings.TrimSpace(input.Name) == "" {
				return "", "", nil, errors.New("bookshelfId and name are required")
			}
			return "rename_bookshelf", input.BookshelfID, input, nil
		})
	addPlanTool(server, "move_bookshelf", "Plan changing a bookshelf parent and order.", plans, config, db,
		func(input MoveBookshelfInput) (string, string, any, error) {
			if input.BookshelfID == "" {
				return "", "", nil, errors.New("bookshelfId is required")
			}
			if input.ParentID != nil && *input.ParentID == input.BookshelfID {
				return "", "", nil, errors.New("a bookshelf cannot contain itself")
			}
			return "move_bookshelf", input.BookshelfID, input, nil
		})
	addPlanTool(server, "delete_bookshelf", "Plan deleting a bookshelf while preserving its books.", plans, config, db,
		func(input EntityIDInput) (string, string, any, error) {
			if input.ID == "" {
				return "", "", nil, errors.New("id is required")
			}
			return "delete_bookshelf", input.ID, input, nil
		})
	addPlanTool(server, "add_book_to_bookshelf", "Plan adding a book to a bookshelf.", plans, config, db,
		func(input BookshelfMembershipInput) (string, string, any, error) {
			if input.BookID == "" || input.BookshelfID == "" {
				return "", "", nil, errors.New("bookId and bookshelfId are required")
			}
			return "add_book_to_bookshelf", input.BookshelfID + "--" + input.BookID, input, nil
		})
	addPlanTool(server, "remove_book_from_bookshelf", "Plan removing a book from a bookshelf.", plans, config, db,
		func(input BookshelfMembershipInput) (string, string, any, error) {
			if input.BookID == "" || input.BookshelfID == "" {
				return "", "", nil, errors.New("bookId and bookshelfId are required")
			}
			return "remove_book_from_bookshelf", input.BookshelfID + "--" + input.BookID, input, nil
		})
	addPlanTool(server, "update_reading_progress", "Plan updating the current reading location.", plans, config, db,
		func(input UpdateReadingProgressInput) (string, string, any, error) {
			if input.BookID == "" || input.Locator == "" || input.Progress < 0 || input.Progress > 1 {
				return "", "", nil, errors.New("bookId and locator are required; progress must be between 0 and 1")
			}
			return "update_reading_progress", input.BookID, input, nil
		})
}

func addPlanTool[I any](server *mcp.Server, name, description string, plans *writePlanStore, config Config, db *sql.DB,
	normalize func(I) (action, entityID string, payload any, err error)) {
	mcp.AddTool(server, &mcp.Tool{Name: name, Description: description + " Returns a plan that requires confirm_write and apply_write."},
		func(ctx context.Context, _ *mcp.CallToolRequest, input I) (*mcp.CallToolResult, PlanWriteOutput, error) {
			if !config.Writable || db == nil {
				return nil, PlanWriteOutput{}, errors.New("MCP writes are disabled")
			}
			action, entityID, payload, err := normalize(input)
			if err != nil {
				return nil, PlanWriteOutput{}, err
			}
			if entityID == "" {
				entityID, err = randomID(entityPrefix(action))
				if err != nil {
					return nil, PlanWriteOutput{}, err
				}
			}
			operationID, err := randomID("op")
			if err != nil {
				return nil, PlanWriteOutput{}, err
			}
			payloadBytes, err := json.Marshal(payload)
			if err != nil {
				return nil, PlanWriteOutput{}, err
			}
			planID, err := randomID("plan")
			if err != nil {
				return nil, PlanWriteOutput{}, err
			}
			expiresAt := time.Now().UTC().Add(5 * time.Minute)
			plans.mu.Lock()
			plans.plans[planID] = excerptWritePlan{Action: action, Payload: payloadBytes, EntityID: entityID, OperationID: operationID, ExpiresAt: expiresAt}
			plans.mu.Unlock()
			return nil, PlanWriteOutput{PlanID: planID, Summary: fmt.Sprintf("%s %s", action, entityID), ExpiresAt: expiresAt}, nil
		})
}

func entityPrefix(action string) string {
	switch action {
	case "create_excerpt":
		return "excerpt"
	case "create_bookmark":
		return "bookmark"
	case "create_bookshelf":
		return "bookshelf"
	default:
		return "entity"
	}
}

func applyManagedPlan(ctx context.Context, db *sql.DB, deviceID, planID string, plan excerptWritePlan) (string, string, error) {
	if deviceID == "" {
		deviceID = "mcp-sidecar"
	}
	if plan.OperationID == "" {
		return "", "", errors.New("write plan has no operation ID")
	}
	now := time.Now().UTC().Format(time.RFC3339Nano)
	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return "", "", fmt.Errorf("begin managed write: %w", err)
	}
	defer tx.Rollback()
	entityType, kind, syncPayload, err := mutateManagedPlan(ctx, tx, plan, now, deviceID)
	if err != nil {
		return "", "", err
	}
	if err := appendSyncOperation(ctx, tx, plan.OperationID, deviceID, entityType, plan.EntityID, kind, syncPayload, now); err != nil {
		return "", "", err
	}
	auditID, err := randomID("audit")
	if err != nil {
		return "", "", err
	}
	parameters, err := json.Marshal(map[string]any{"planId": planID, "entityId": plan.EntityID, "payload": json.RawMessage(plan.Payload)})
	if err != nil {
		return "", "", err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO audit_events (id, caller, action, parameters_json, result, occurred_at)
		VALUES (?, 'mcp', ?, ?, 'applied', ?)`, auditID, plan.Action, string(parameters), now); err != nil {
		return "", "", fmt.Errorf("append audit event: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return "", "", fmt.Errorf("commit managed write: %w", err)
	}
	return plan.EntityID, plan.OperationID, nil
}

func mutateManagedPlan(ctx context.Context, tx *sql.Tx, plan excerptWritePlan, now, deviceID string) (string, string, map[string]any, error) {
	payload := map[string]any{}
	if err := json.Unmarshal(plan.Payload, &payload); err != nil {
		return "", "", nil, err
	}
	requireAffected := func(result sql.Result, err error, label string) error {
		if err != nil {
			return fmt.Errorf("%s: %w", label, err)
		}
		count, err := result.RowsAffected()
		if err != nil {
			return err
		}
		if count != 1 {
			return fmt.Errorf("%s: entity does not exist", label)
		}
		return nil
	}
	switch plan.Action {
	case "update_book_metadata":
		var sha, media string
		var md5 *string
		var cover *string
		if err := tx.QueryRowContext(ctx, `SELECT sha256, md5, media_type, cover_sha256 FROM books WHERE id=? AND is_deleted=0`, plan.EntityID).Scan(&sha, &md5, &media, &cover); err != nil {
			return "", "", nil, fmt.Errorf("load book: %w", err)
		}
		title := strings.TrimSpace(payload["title"].(string))
		result, err := tx.ExecContext(ctx, `UPDATE books SET title=?,author=?,description=?,rating=?,updated_at=? WHERE id=? AND is_deleted=0`, title, payload["author"], payload["description"], payload["rating"], now, plan.EntityID)
		if err := requireAffected(result, err, "update book"); err != nil {
			return "", "", nil, err
		}
		return "book", "upsert", map[string]any{"id": plan.EntityID, "sha256": sha, "md5": md5, "title": title, "author": payload["author"], "description": payload["description"], "mediaType": media, "coverSha256": cover, "rating": payload["rating"]}, nil
	case "delete_book":
		result, err := tx.ExecContext(ctx, `UPDATE books SET is_deleted=1,updated_at=? WHERE id=? AND is_deleted=0`, now, plan.EntityID)
		return "book", "delete", map[string]any{}, requireAffected(result, err, "delete book")
	case "create_excerpt":
		result, err := tx.ExecContext(ctx, `INSERT INTO excerpts (id,book_id,locator,quote,note,color,is_deleted,created_at,updated_at) VALUES (?,?,?,?,?,?,0,?,?)`, plan.EntityID, payload["bookId"], payload["locator"], payload["quote"], payload["note"], payload["color"], now, now)
		return "excerpt", "upsert", mergeID(plan.EntityID, payload), requireAffected(result, err, "create excerpt")
	case "update_excerpt":
		var bookID, locator, quote string
		if err := tx.QueryRowContext(ctx, `SELECT book_id,locator,quote FROM excerpts WHERE id=? AND is_deleted=0`, plan.EntityID).Scan(&bookID, &locator, &quote); err != nil {
			return "", "", nil, fmt.Errorf("load excerpt: %w", err)
		}
		result, err := tx.ExecContext(ctx, `UPDATE excerpts SET note=?,color=?,updated_at=? WHERE id=? AND is_deleted=0`, payload["note"], payload["color"], now, plan.EntityID)
		if err := requireAffected(result, err, "update excerpt"); err != nil {
			return "", "", nil, err
		}
		return "excerpt", "upsert", map[string]any{"id": plan.EntityID, "bookId": bookID, "locator": locator, "quote": quote, "note": payload["note"], "color": payload["color"]}, nil
	case "delete_excerpt":
		result, err := tx.ExecContext(ctx, `UPDATE excerpts SET is_deleted=1,updated_at=? WHERE id=? AND is_deleted=0`, now, plan.EntityID)
		return "excerpt", "delete", map[string]any{}, requireAffected(result, err, "delete excerpt")
	case "create_bookmark":
		result, err := tx.ExecContext(ctx, `INSERT INTO bookmarks (id,book_id,locator,title,note,is_deleted,created_at,updated_at) VALUES (?,?,?,?,?,0,?,?)`, plan.EntityID, payload["bookId"], payload["locator"], payload["title"], payload["note"], now, now)
		return "bookmark", "upsert", mergeID(plan.EntityID, payload), requireAffected(result, err, "create bookmark")
	case "update_bookmark":
		var bookID, locator string
		if err := tx.QueryRowContext(ctx, `SELECT book_id,locator FROM bookmarks WHERE id=? AND is_deleted=0`, plan.EntityID).Scan(&bookID, &locator); err != nil {
			return "", "", nil, fmt.Errorf("load bookmark: %w", err)
		}
		result, err := tx.ExecContext(ctx, `UPDATE bookmarks SET title=?,note=?,updated_at=? WHERE id=? AND is_deleted=0`, payload["title"], payload["note"], now, plan.EntityID)
		if err := requireAffected(result, err, "update bookmark"); err != nil {
			return "", "", nil, err
		}
		return "bookmark", "upsert", map[string]any{"id": plan.EntityID, "bookId": bookID, "locator": locator, "title": payload["title"], "note": payload["note"]}, nil
	case "delete_bookmark":
		result, err := tx.ExecContext(ctx, `UPDATE bookmarks SET is_deleted=1,updated_at=? WHERE id=? AND is_deleted=0`, now, plan.EntityID)
		return "bookmark", "delete", map[string]any{}, requireAffected(result, err, "delete bookmark")
	case "create_bookshelf":
		result, err := tx.ExecContext(ctx, `INSERT INTO bookshelves (id,parent_id,name,sort_order,is_deleted,created_at,updated_at) VALUES (?,?,?,?,0,?,?)`, plan.EntityID, payload["parentId"], strings.TrimSpace(payload["name"].(string)), payload["sortOrder"], now, now)
		return "bookshelf", "upsert", mergeID(plan.EntityID, payload), requireAffected(result, err, "create bookshelf")
	case "rename_bookshelf", "move_bookshelf":
		var parentID *string
		var name string
		var sortOrder int
		if err := tx.QueryRowContext(ctx, `SELECT parent_id,name,sort_order FROM bookshelves WHERE id=? AND is_deleted=0`, plan.EntityID).Scan(&parentID, &name, &sortOrder); err != nil {
			return "", "", nil, fmt.Errorf("load bookshelf: %w", err)
		}
		if plan.Action == "rename_bookshelf" {
			name = strings.TrimSpace(payload["name"].(string))
		} else {
			parentID = optionalString(payload["parentId"])
			sortOrder = intFromJSON(payload["sortOrder"])
		}
		if parentID != nil {
			if err := validateBookshelfParent(ctx, tx, plan.EntityID, *parentID); err != nil {
				return "", "", nil, err
			}
		}
		result, err := tx.ExecContext(ctx, `UPDATE bookshelves SET parent_id=?,name=?,sort_order=?,updated_at=? WHERE id=? AND is_deleted=0`, parentID, name, sortOrder, now, plan.EntityID)
		if err := requireAffected(result, err, "update bookshelf"); err != nil {
			return "", "", nil, err
		}
		return "bookshelf", "upsert", map[string]any{"id": plan.EntityID, "parentId": parentID, "name": name, "sortOrder": sortOrder}, nil
	case "delete_bookshelf":
		result, err := tx.ExecContext(ctx, `UPDATE bookshelves SET is_deleted=1,updated_at=? WHERE id=? AND is_deleted=0`, now, plan.EntityID)
		if err := requireAffected(result, err, "delete bookshelf"); err != nil {
			return "", "", nil, err
		}
		if _, err := tx.ExecContext(ctx, `UPDATE bookshelves SET parent_id=NULL,updated_at=? WHERE parent_id=?`, now, plan.EntityID); err != nil {
			return "", "", nil, err
		}
		return "bookshelf", "delete", map[string]any{}, nil
	case "add_book_to_bookshelf", "remove_book_from_bookshelf":
		if plan.Action == "add_book_to_bookshelf" {
			_, err := tx.ExecContext(ctx, `INSERT INTO bookshelf_entries (bookshelf_id,book_id,sort_order,updated_at) VALUES (?,?,?,?) ON CONFLICT(bookshelf_id,book_id) DO UPDATE SET sort_order=excluded.sort_order,updated_at=excluded.updated_at`, payload["bookshelfId"], payload["bookId"], payload["sortOrder"], now)
			return "bookshelfEntry", "upsert", payload, err
		}
		_, err := tx.ExecContext(ctx, `DELETE FROM bookshelf_entries WHERE bookshelf_id=? AND book_id=?`, payload["bookshelfId"], payload["bookId"])
		return "bookshelfEntry", "delete", payload, err
	case "move_book":
		return mutateMoveBook(ctx, tx, plan, now, deviceID, payload)
	case "update_reading_progress":
		_, err := tx.ExecContext(ctx, `INSERT INTO reading_progresses (book_id,locator,progress,chapter_title,page,device_id,updated_at) VALUES (?,?,?,?,?,?,?) ON CONFLICT(book_id) DO UPDATE SET locator=excluded.locator,progress=excluded.progress,chapter_title=excluded.chapter_title,page=excluded.page,device_id=excluded.device_id,updated_at=excluded.updated_at`, plan.EntityID, payload["locator"], payload["progress"], payload["chapterTitle"], payload["page"], deviceID, now)
		return "readingProgress", "upsert", map[string]any{"locator": payload["locator"], "progress": payload["progress"], "chapterTitle": payload["chapterTitle"], "page": payload["page"]}, err
	default:
		return "", "", nil, fmt.Errorf("unsupported write action %q", plan.Action)
	}
}

func mutateMoveBook(ctx context.Context, tx *sql.Tx, plan excerptWritePlan, now, deviceID string, payload map[string]any) (string, string, map[string]any, error) {
	bookID := payload["bookId"].(string)
	target := payload["bookshelfId"].(string)
	rows, err := tx.QueryContext(ctx, `SELECT bookshelf_id FROM bookshelf_entries WHERE book_id=? AND bookshelf_id<>?`, bookID, target)
	if err != nil {
		return "", "", nil, err
	}
	var previous []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return "", "", nil, err
		}
		previous = append(previous, id)
	}
	if err := rows.Close(); err != nil {
		return "", "", nil, err
	}
	for _, shelfID := range previous {
		if _, err := tx.ExecContext(ctx, `DELETE FROM bookshelf_entries WHERE bookshelf_id=? AND book_id=?`, shelfID, bookID); err != nil {
			return "", "", nil, err
		}
		opID, err := randomID("op")
		if err != nil {
			return "", "", nil, err
		}
		p := map[string]any{"bookshelfId": shelfID, "bookId": bookID}
		if err := appendSyncOperation(ctx, tx, opID, deviceID, "bookshelfEntry", shelfID+"--"+bookID, "delete", p, now); err != nil {
			return "", "", nil, err
		}
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO bookshelf_entries (bookshelf_id,book_id,sort_order,updated_at) VALUES (?,?,?,?) ON CONFLICT(bookshelf_id,book_id) DO UPDATE SET sort_order=excluded.sort_order,updated_at=excluded.updated_at`, target, bookID, payload["sortOrder"], now)
	return "bookshelfEntry", "upsert", map[string]any{"bookshelfId": target, "bookId": bookID, "sortOrder": payload["sortOrder"]}, err
}

func appendSyncOperation(ctx context.Context, tx *sql.Tx, operationID, deviceID, entityType, entityID, kind string, payload map[string]any, now string) error {
	bytes, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `INSERT INTO sync_operations (operation_id,device_id,entity_type,entity_id,kind,payload_json,occurred_at,applied_at) VALUES (?,?,?,?,?,?,?,NULL)`, operationID, deviceID, entityType, entityID, kind, string(bytes), now); err != nil {
		return fmt.Errorf("append sync operation: %w", err)
	}
	return nil
}
func mergeID(id string, payload map[string]any) map[string]any {
	result := map[string]any{"id": id}
	for key, value := range payload {
		result[key] = value
	}
	return result
}
func optionalString(value any) *string {
	if value == nil {
		return nil
	}
	text, ok := value.(string)
	if !ok || text == "" {
		return nil
	}
	return &text
}
func intFromJSON(value any) int {
	if number, ok := value.(float64); ok {
		return int(number)
	}
	if number, ok := value.(int); ok {
		return number
	}
	return 0
}
func validateBookshelfParent(ctx context.Context, tx *sql.Tx, bookshelfID, parentID string) error {
	cursor := parentID
	for cursor != "" {
		if cursor == bookshelfID {
			return errors.New("moving the bookshelf would create a cycle")
		}
		var parent *string
		if err := tx.QueryRowContext(ctx, `SELECT parent_id FROM bookshelves WHERE id=? AND is_deleted=0`, cursor).Scan(&parent); err != nil {
			return fmt.Errorf("validate bookshelf parent: %w", err)
		}
		if parent == nil {
			return nil
		}
		cursor = *parent
	}
	return nil
}
