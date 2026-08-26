package server

import (
	"archive/zip"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"html"
	"io"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/modelcontextprotocol/go-sdk/mcp"
)

type QueryInput struct {
	Query  string `json:"query" jsonschema:"Case-insensitive search query"`
	BookID string `json:"bookId,omitempty" jsonschema:"Optional stable book ID filter"`
}

type BookIDInput struct {
	BookID string `json:"bookId" jsonschema:"Stable Leeef book ID"`
}

type BookDetails struct {
	ID          string   `json:"id"`
	SHA256      string   `json:"sha256"`
	MD5         *string  `json:"md5,omitempty"`
	Title       string   `json:"title"`
	Author      *string  `json:"author,omitempty"`
	Description *string  `json:"description,omitempty"`
	MediaType   string   `json:"mediaType"`
	Rating      *float64 `json:"rating,omitempty"`
	Available   bool     `json:"availableLocally"`
	CreatedAt   string   `json:"createdAt"`
	UpdatedAt   string   `json:"updatedAt"`
}

type BookOutput struct {
	Book BookDetails `json:"book"`
}

type SearchBooksOutput struct {
	Books []BookDetails `json:"books"`
}

type BookContentOutput struct {
	BookID    string `json:"bookId"`
	MediaType string `json:"mediaType"`
	Content   string `json:"content"`
}

type ExcerptSummary struct {
	ID        string  `json:"id"`
	BookID    string  `json:"bookId"`
	Locator   string  `json:"locator"`
	Quote     string  `json:"quote"`
	Note      *string `json:"note,omitempty"`
	Color     string  `json:"color"`
	CreatedAt string  `json:"createdAt"`
	UpdatedAt string  `json:"updatedAt"`
}

type ExcerptsOutput struct {
	Excerpts []ExcerptSummary `json:"excerpts"`
}

type BookmarkSummary struct {
	ID        string  `json:"id"`
	BookID    string  `json:"bookId"`
	Locator   string  `json:"locator"`
	Title     *string `json:"title,omitempty"`
	Note      *string `json:"note,omitempty"`
	CreatedAt string  `json:"createdAt"`
	UpdatedAt string  `json:"updatedAt"`
}

type BookmarksOutput struct {
	Bookmarks []BookmarkSummary `json:"bookmarks"`
}

type BookshelfSummary struct {
	ID        string   `json:"id"`
	ParentID  *string  `json:"parentId,omitempty"`
	Name      string   `json:"name"`
	SortOrder int      `json:"sortOrder"`
	BookIDs   []string `json:"bookIds"`
}

type BookshelvesOutput struct {
	Bookshelves []BookshelfSummary `json:"bookshelves"`
}

type ReadingProgressOutput struct {
	BookID       string  `json:"bookId"`
	Locator      string  `json:"locator"`
	Progress     float64 `json:"progress"`
	ChapterTitle *string `json:"chapterTitle,omitempty"`
	Page         *int    `json:"page,omitempty"`
	DeviceID     string  `json:"deviceId"`
	UpdatedAt    string  `json:"updatedAt"`
}

func registerReadCapabilities(server *mcp.Server, db *sql.DB) {
	mcp.AddTool(server, &mcp.Tool{Name: "search_books", Description: "Search visible books by title, author, or description."}, func(ctx context.Context, _ *mcp.CallToolRequest, input QueryInput) (*mcp.CallToolResult, SearchBooksOutput, error) {
		books, err := queryBooks(ctx, db, input.Query)
		return nil, SearchBooksOutput{Books: books}, err
	})
	mcp.AddTool(server, &mcp.Tool{Name: "get_book", Description: "Get complete metadata for one visible book."}, func(ctx context.Context, _ *mcp.CallToolRequest, input BookIDInput) (*mcp.CallToolResult, BookOutput, error) {
		book, err := queryBook(ctx, db, input.BookID)
		return nil, BookOutput{Book: book}, err
	})
	mcp.AddTool(server, &mcp.Tool{Name: "get_book_content", Description: "Extract readable text from a locally available TXT, EPUB, or FB2 book."}, func(ctx context.Context, _ *mcp.CallToolRequest, input BookIDInput) (*mcp.CallToolResult, BookContentOutput, error) {
		content, mediaType, err := readBookContent(ctx, db, input.BookID)
		return nil, BookContentOutput{BookID: input.BookID, MediaType: mediaType, Content: content}, err
	})
	mcp.AddTool(server, &mcp.Tool{Name: "list_excerpts", Description: "List visible excerpts, optionally for one book."}, func(ctx context.Context, _ *mcp.CallToolRequest, input QueryInput) (*mcp.CallToolResult, ExcerptsOutput, error) {
		items, err := queryExcerpts(ctx, db, input.BookID, "")
		return nil, ExcerptsOutput{Excerpts: items}, err
	})
	mcp.AddTool(server, &mcp.Tool{Name: "search_excerpts", Description: "Search excerpt quotes and notes."}, func(ctx context.Context, _ *mcp.CallToolRequest, input QueryInput) (*mcp.CallToolResult, ExcerptsOutput, error) {
		items, err := queryExcerpts(ctx, db, input.BookID, input.Query)
		return nil, ExcerptsOutput{Excerpts: items}, err
	})
	mcp.AddTool(server, &mcp.Tool{Name: "list_bookmarks", Description: "List visible bookmarks, optionally for one book."}, func(ctx context.Context, _ *mcp.CallToolRequest, input QueryInput) (*mcp.CallToolResult, BookmarksOutput, error) {
		items, err := queryBookmarks(ctx, db, input.BookID)
		return nil, BookmarksOutput{Bookmarks: items}, err
	})
	mcp.AddTool(server, &mcp.Tool{Name: "list_bookshelves", Description: "List the bookshelf hierarchy and book membership."}, func(ctx context.Context, _ *mcp.CallToolRequest, _ struct{}) (*mcp.CallToolResult, BookshelvesOutput, error) {
		items, err := queryBookshelves(ctx, db)
		return nil, BookshelvesOutput{Bookshelves: items}, err
	})
	mcp.AddTool(server, &mcp.Tool{Name: "get_reading_progress", Description: "Get current reading progress for a book."}, func(ctx context.Context, _ *mcp.CallToolRequest, input BookIDInput) (*mcp.CallToolResult, ReadingProgressOutput, error) {
		item, err := queryReadingProgress(ctx, db, input.BookID)
		return nil, item, err
	})

	server.AddResource(&mcp.Resource{Name: "Leeef library", URI: "leeef://library", MIMEType: "application/json"}, resourceHandler(db))
	for _, template := range []struct{ name, uri, mime string }{
		{"Book metadata", "leeef://books/{bookId}", "application/json"},
		{"Book content", "leeef://books/{bookId}/content", "text/plain"},
		{"Book excerpts", "leeef://books/{bookId}/excerpts", "application/json"},
		{"Book bookmarks", "leeef://books/{bookId}/bookmarks", "application/json"},
		{"Bookshelf", "leeef://bookshelves/{bookshelfId}", "application/json"},
	} {
		server.AddResourceTemplate(&mcp.ResourceTemplate{Name: template.name, URITemplate: template.uri, MIMEType: template.mime}, resourceHandler(db))
	}
}

func resourceHandler(db *sql.DB) mcp.ResourceHandler {
	return func(ctx context.Context, request *mcp.ReadResourceRequest) (*mcp.ReadResourceResult, error) {
		uri := request.Params.URI
		parsed, err := url.Parse(uri)
		if err != nil || parsed.Scheme != "leeef" {
			return nil, fmt.Errorf("invalid Leeef resource URI %q", uri)
		}
		parts := strings.FieldsFunc(parsed.Host+parsed.Path, func(r rune) bool { return r == '/' })
		var value any
		mime := "application/json"
		switch {
		case len(parts) == 1 && parts[0] == "library":
			books, err := queryBooks(ctx, db, "")
			if err != nil {
				return nil, err
			}
			value = SearchBooksOutput{Books: books}
		case len(parts) == 2 && parts[0] == "books":
			book, err := queryBook(ctx, db, parts[1])
			if err != nil {
				return nil, err
			}
			value = book
		case len(parts) == 3 && parts[0] == "books" && parts[2] == "content":
			content, _, err := readBookContent(ctx, db, parts[1])
			if err != nil {
				return nil, err
			}
			value, mime = content, "text/plain"
		case len(parts) == 3 && parts[0] == "books" && parts[2] == "excerpts":
			items, err := queryExcerpts(ctx, db, parts[1], "")
			if err != nil {
				return nil, err
			}
			value = ExcerptsOutput{Excerpts: items}
		case len(parts) == 3 && parts[0] == "books" && parts[2] == "bookmarks":
			items, err := queryBookmarks(ctx, db, parts[1])
			if err != nil {
				return nil, err
			}
			value = BookmarksOutput{Bookmarks: items}
		case len(parts) == 2 && parts[0] == "bookshelves":
			items, err := queryBookshelves(ctx, db)
			if err != nil {
				return nil, err
			}
			for _, item := range items {
				if item.ID == parts[1] {
					value = item
					break
				}
			}
			if value == nil {
				return nil, errors.New("bookshelf does not exist")
			}
		default:
			return nil, fmt.Errorf("unknown Leeef resource %q", uri)
		}
		text, ok := value.(string)
		if !ok {
			bytes, err := json.MarshalIndent(value, "", "  ")
			if err != nil {
				return nil, err
			}
			text = string(bytes)
		}
		return &mcp.ReadResourceResult{Contents: []*mcp.ResourceContents{{URI: uri, MIMEType: mime, Text: text}}}, nil
	}
}

func queryBooks(ctx context.Context, db *sql.DB, query string) ([]BookDetails, error) {
	if db == nil {
		return nil, errors.New("database path was not configured")
	}
	pattern := "%" + strings.ToLower(query) + "%"
	rows, err := db.QueryContext(ctx, `SELECT id, sha256, md5, title, author, description, media_type, rating,
		is_available_locally, created_at, updated_at FROM books WHERE is_deleted = 0 AND
		(? = '%%' OR lower(title) LIKE ? OR lower(coalesce(author,'')) LIKE ? OR lower(coalesce(description,'')) LIKE ?)
		ORDER BY updated_at DESC`, pattern, pattern, pattern, pattern)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []BookDetails{}
	for rows.Next() {
		var x BookDetails
		if err := rows.Scan(&x.ID, &x.SHA256, &x.MD5, &x.Title, &x.Author, &x.Description, &x.MediaType, &x.Rating, &x.Available, &x.CreatedAt, &x.UpdatedAt); err != nil {
			return nil, err
		}
		items = append(items, x)
	}
	return items, rows.Err()
}

func queryBook(ctx context.Context, db *sql.DB, id string) (BookDetails, error) {
	if db == nil {
		return BookDetails{}, errors.New("database path was not configured")
	}
	var item BookDetails
	err := db.QueryRowContext(ctx, `SELECT id, sha256, md5, title, author, description, media_type, rating,
		is_available_locally, created_at, updated_at FROM books WHERE id = ? AND is_deleted = 0`, id).
		Scan(&item.ID, &item.SHA256, &item.MD5, &item.Title, &item.Author, &item.Description,
			&item.MediaType, &item.Rating, &item.Available, &item.CreatedAt, &item.UpdatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return BookDetails{}, errors.New("book does not exist")
	}
	return item, err
}

func queryExcerpts(ctx context.Context, db *sql.DB, bookID, query string) ([]ExcerptSummary, error) {
	pattern := "%" + strings.ToLower(query) + "%"
	rows, err := db.QueryContext(ctx, `SELECT id,book_id,locator,quote,note,color,created_at,updated_at FROM excerpts
		WHERE is_deleted=0 AND (?='' OR book_id=?) AND (?='%%' OR lower(quote) LIKE ? OR lower(coalesce(note,'')) LIKE ?) ORDER BY updated_at DESC`, bookID, bookID, pattern, pattern, pattern)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []ExcerptSummary{}
	for rows.Next() {
		var x ExcerptSummary
		if err := rows.Scan(&x.ID, &x.BookID, &x.Locator, &x.Quote, &x.Note, &x.Color, &x.CreatedAt, &x.UpdatedAt); err != nil {
			return nil, err
		}
		items = append(items, x)
	}
	return items, rows.Err()
}

func queryBookmarks(ctx context.Context, db *sql.DB, bookID string) ([]BookmarkSummary, error) {
	rows, err := db.QueryContext(ctx, `SELECT id,book_id,locator,title,note,created_at,updated_at FROM bookmarks WHERE is_deleted=0 AND (?='' OR book_id=?) ORDER BY updated_at DESC`, bookID, bookID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []BookmarkSummary{}
	for rows.Next() {
		var x BookmarkSummary
		if err := rows.Scan(&x.ID, &x.BookID, &x.Locator, &x.Title, &x.Note, &x.CreatedAt, &x.UpdatedAt); err != nil {
			return nil, err
		}
		items = append(items, x)
	}
	return items, rows.Err()
}

func queryBookshelves(ctx context.Context, db *sql.DB) ([]BookshelfSummary, error) {
	rows, err := db.QueryContext(ctx, `SELECT id,parent_id,name,sort_order FROM bookshelves WHERE is_deleted=0 ORDER BY sort_order,name`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	items := []BookshelfSummary{}
	for rows.Next() {
		var x BookshelfSummary
		if err := rows.Scan(&x.ID, &x.ParentID, &x.Name, &x.SortOrder); err != nil {
			return nil, err
		}
		x.BookIDs = []string{}
		items = append(items, x)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if err := rows.Close(); err != nil {
		return nil, err
	}
	for index := range items {
		membership, err := db.QueryContext(ctx, `SELECT book_id FROM bookshelf_entries WHERE bookshelf_id=? ORDER BY sort_order`, items[index].ID)
		if err != nil {
			return nil, err
		}
		for membership.Next() {
			var id string
			if err := membership.Scan(&id); err != nil {
				membership.Close()
				return nil, err
			}
			items[index].BookIDs = append(items[index].BookIDs, id)
		}
		membership.Close()
	}
	return items, nil
}

func queryReadingProgress(ctx context.Context, db *sql.DB, bookID string) (ReadingProgressOutput, error) {
	var x ReadingProgressOutput
	err := db.QueryRowContext(ctx, `SELECT book_id,locator,progress,chapter_title,page,device_id,updated_at FROM reading_progresses WHERE book_id=?`, bookID).Scan(&x.BookID, &x.Locator, &x.Progress, &x.ChapterTitle, &x.Page, &x.DeviceID, &x.UpdatedAt)
	if err == sql.ErrNoRows {
		return x, errors.New("reading progress does not exist")
	}
	return x, err
}

func readBookContent(ctx context.Context, db *sql.DB, bookID string) (string, string, error) {
	var path, media string
	if err := db.QueryRowContext(ctx, `SELECT file_path,media_type FROM books WHERE id=? AND is_deleted=0`, bookID).Scan(&path, &media); err != nil {
		return "", "", err
	}
	switch media {
	case "text/plain":
		bytes, err := os.ReadFile(path)
		return strings.ToValidUTF8(string(bytes), "�"), media, err
	case "application/epub+zip":
		text, err := extractEPUB(path)
		return text, media, err
	case "application/x-fictionbook+xml":
		bytes, err := os.ReadFile(path)
		if err != nil {
			return "", media, err
		}
		return stripMarkup(string(bytes)), media, nil
	default:
		return "", media, fmt.Errorf("text extraction is not available for %s", media)
	}
}

var scriptStylePattern = regexp.MustCompile(`(?is)<script[^>]*>.*?</script>|<style[^>]*>.*?</style>`)
var markupPattern = regexp.MustCompile(`(?s)<[^>]+>`)
var whitespacePattern = regexp.MustCompile(`\s+`)

func stripMarkup(value string) string {
	withoutExecutableMarkup := scriptStylePattern.ReplaceAllString(value, " ")
	return strings.TrimSpace(whitespacePattern.ReplaceAllString(html.UnescapeString(markupPattern.ReplaceAllString(withoutExecutableMarkup, " ")), " "))
}
func extractEPUB(path string) (string, error) {
	archive, err := zip.OpenReader(filepath.Clean(path))
	if err != nil {
		return "", err
	}
	defer archive.Close()
	parts := []string{}
	for _, file := range archive.File {
		lower := strings.ToLower(file.Name)
		if !strings.HasSuffix(lower, ".xhtml") && !strings.HasSuffix(lower, ".html") && !strings.HasSuffix(lower, ".htm") {
			continue
		}
		reader, err := file.Open()
		if err != nil {
			return "", err
		}
		bytes, err := io.ReadAll(io.LimitReader(reader, 16<<20))
		reader.Close()
		if err != nil {
			return "", err
		}
		if text := stripMarkup(string(bytes)); text != "" {
			parts = append(parts, text)
		}
	}
	if len(parts) == 0 {
		return "", errors.New("EPUB contains no readable XHTML")
	}
	return strings.Join(parts, "\n\n"), nil
}
