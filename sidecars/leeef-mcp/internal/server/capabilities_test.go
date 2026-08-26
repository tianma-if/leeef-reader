package server

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestReadResourcesAndCompleteToolRegistry(t *testing.T) {
	databasePath, textPath := createFullTestDatabase(t)
	server, err := New(Config{Token: "secret", DatabasePath: databasePath, DeviceID: "mcp-test", Writable: true})
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	httpServer := httptest.NewServer(server)
	defer httpServer.Close()
	sessionID := initializeMCP(t, httpServer.URL)

	_, listed := postMCP(t, httpServer.URL, sessionID, `{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}`)
	tools := listed["result"].(map[string]any)["tools"].([]any)
	names := map[string]bool{}
	for _, item := range tools {
		names[item.(map[string]any)["name"].(string)] = true
	}
	for _, name := range []string{
		"list_books", "search_books", "get_book", "get_book_content", "update_book_metadata", "move_book", "delete_book",
		"list_excerpts", "search_excerpts", "create_excerpt", "update_excerpt", "delete_excerpt",
		"list_bookmarks", "create_bookmark", "update_bookmark", "delete_bookmark", "list_bookshelves", "create_bookshelf",
		"rename_bookshelf", "move_bookshelf", "delete_bookshelf", "add_book_to_bookshelf", "remove_book_from_bookshelf",
		"get_reading_progress", "update_reading_progress", "confirm_write", "apply_write",
	} {
		if !names[name] {
			t.Errorf("tool %s is missing", name)
		}
	}

	_, library := postMCP(t, httpServer.URL, sessionID, `{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"leeef://library"}}`)
	contents := library["result"].(map[string]any)["contents"].([]any)
	if len(contents) != 1 {
		t.Fatalf("library contents = %#v", contents)
	}

	_, content := postMCP(t, httpServer.URL, sessionID, `{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_book_content","arguments":{"bookId":"book-1"}}}`)
	if got := toolStructured(t, content)["content"]; got != "Hello from Leeef" {
		t.Fatalf("content = %#v", got)
	}
	if _, err := os.Stat(textPath); err != nil {
		t.Fatal(err)
	}
}

func TestManagedWritesAreConfirmedSyncedAuditedAndIdempotent(t *testing.T) {
	databasePath, _ := createFullTestDatabase(t)
	server, err := New(Config{Token: "secret", DatabasePath: databasePath, DeviceID: "mcp-test", Writable: true})
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	httpServer := httptest.NewServer(server)
	defer httpServer.Close()
	sessionID := initializeMCP(t, httpServer.URL)

	shelf := callPlanAndApply(t, httpServer.URL, sessionID, "create_bookshelf", map[string]any{"name": "AI Reading", "sortOrder": 0})
	shelfID := shelf["entityId"].(string)
	bookmark := callPlanAndApply(t, httpServer.URL, sessionID, "create_bookmark", map[string]any{"bookId": "book-1", "locator": "page:1", "title": "Start"})
	bookmarkID := bookmark["entityId"].(string)
	callPlanAndApply(t, httpServer.URL, sessionID, "add_book_to_bookshelf", map[string]any{"bookshelfId": shelfID, "bookId": "book-1", "sortOrder": 2})
	callPlanAndApply(t, httpServer.URL, sessionID, "update_reading_progress", map[string]any{"bookId": "book-1", "locator": "page:2", "progress": 0.5, "page": 2})

	verification, err := sql.Open("sqlite", databasePath)
	if err != nil {
		t.Fatal(err)
	}
	defer verification.Close()
	for table, want := range map[string]int{"bookshelves": 2, "bookmarks": 1, "bookshelf_entries": 2, "reading_progresses": 1, "sync_operations": 4, "audit_events": 4} {
		var count int
		if err := verification.QueryRow("SELECT count(*) FROM " + table).Scan(&count); err != nil {
			t.Fatal(err)
		}
		if count != want {
			t.Errorf("%s count = %d, want %d", table, count, want)
		}
	}
	var storedTitle string
	if err := verification.QueryRow(`SELECT title FROM bookmarks WHERE id=?`, bookmarkID).Scan(&storedTitle); err != nil {
		t.Fatal(err)
	}
	if storedTitle != "Start" {
		t.Fatalf("bookmark title = %q", storedTitle)
	}

	// Retrying the same apply request returns the recorded result without a duplicate operation.
	planID := shelf["_planId"].(string)
	token := shelf["_confirmationToken"].(string)
	body := fmt.Sprintf(`{"jsonrpc":"2.0","id":99,"method":"tools/call","params":{"name":"apply_write","arguments":{"planId":%q,"confirmationToken":%q}}}`, planID, token)
	_, retried := postMCP(t, httpServer.URL, sessionID, body)
	if toolStructured(t, retried)["operationId"] != shelf["operationId"] {
		t.Fatalf("retry response = %#v", retried)
	}
	var operations int
	if err := verification.QueryRow(`SELECT count(*) FROM sync_operations`).Scan(&operations); err != nil {
		t.Fatal(err)
	}
	if operations != 4 {
		t.Fatalf("retry created duplicate operation: %d", operations)
	}
}

func initializeMCP(t *testing.T, endpoint string) string {
	t.Helper()
	sessionID, _ := postMCP(t, endpoint, "", `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}`)
	postMCP(t, endpoint, sessionID, `{"jsonrpc":"2.0","method":"notifications/initialized"}`)
	return sessionID
}

func callPlanAndApply(t *testing.T, endpoint, sessionID, tool string, arguments map[string]any) map[string]any {
	t.Helper()
	encoded, _ := json.Marshal(arguments)
	_, planned := postMCP(t, endpoint, sessionID, fmt.Sprintf(`{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":%q,"arguments":%s}}`, tool, encoded))
	planID := toolStructured(t, planned)["planId"].(string)
	_, confirmed := postMCP(t, endpoint, sessionID, fmt.Sprintf(`{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"confirm_write","arguments":{"planId":%q}}}`, planID))
	token := toolStructured(t, confirmed)["confirmationToken"].(string)
	_, applied := postMCP(t, endpoint, sessionID, fmt.Sprintf(`{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"apply_write","arguments":{"planId":%q,"confirmationToken":%q}}}`, planID, token))
	result := toolStructured(t, applied)
	result["_planId"] = planID
	result["_confirmationToken"] = token
	return result
}

func createFullTestDatabase(t *testing.T) (string, string) {
	t.Helper()
	directory := t.TempDir()
	databasePath := filepath.Join(directory, "leeef.sqlite")
	textPath := filepath.Join(directory, "hello.txt")
	if err := os.WriteFile(textPath, []byte("Hello from Leeef"), 0o600); err != nil {
		t.Fatal(err)
	}
	db, err := sql.Open("sqlite", databasePath)
	if err != nil {
		t.Fatal(err)
	}
	statements := []string{
		`CREATE TABLE books (id TEXT PRIMARY KEY,sha256 TEXT NOT NULL,md5 TEXT,title TEXT NOT NULL,author TEXT,description TEXT,media_type TEXT NOT NULL,file_path TEXT,cover_path TEXT,cover_sha256 TEXT,rating REAL,is_available_locally INTEGER NOT NULL,is_deleted INTEGER NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)`,
		`CREATE TABLE excerpts (id TEXT PRIMARY KEY,book_id TEXT NOT NULL,locator TEXT NOT NULL,quote TEXT NOT NULL,note TEXT,color TEXT NOT NULL,is_deleted INTEGER NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)`,
		`CREATE TABLE bookmarks (id TEXT PRIMARY KEY,book_id TEXT NOT NULL,locator TEXT NOT NULL,title TEXT,note TEXT,is_deleted INTEGER NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)`,
		`CREATE TABLE bookshelves (id TEXT PRIMARY KEY,parent_id TEXT,name TEXT NOT NULL,sort_order INTEGER NOT NULL,is_deleted INTEGER NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)`,
		`CREATE TABLE bookshelf_entries (bookshelf_id TEXT NOT NULL,book_id TEXT NOT NULL,sort_order INTEGER NOT NULL,updated_at TEXT NOT NULL,PRIMARY KEY(bookshelf_id,book_id))`,
		`CREATE TABLE reading_progresses (book_id TEXT PRIMARY KEY,locator TEXT NOT NULL,progress REAL NOT NULL,chapter_title TEXT,page INTEGER,device_id TEXT NOT NULL,updated_at TEXT NOT NULL)`,
		`CREATE TABLE sync_operations (operation_id TEXT PRIMARY KEY,device_id TEXT NOT NULL,entity_type TEXT NOT NULL,entity_id TEXT NOT NULL,kind TEXT NOT NULL,payload_json TEXT,occurred_at TEXT NOT NULL,applied_at TEXT)`,
		`CREATE TABLE audit_events (id TEXT PRIMARY KEY,caller TEXT NOT NULL,action TEXT NOT NULL,parameters_json TEXT NOT NULL,result TEXT NOT NULL,occurred_at TEXT NOT NULL)`,
		fmt.Sprintf(`INSERT INTO books VALUES ('book-1','%s',NULL,'Hello','Leeef','A test book','text/plain',%q,NULL,NULL,4,1,0,'2026-01-01','2026-01-01')`, stringsOf('a', 64), textPath),
		`INSERT INTO bookshelves VALUES ('shelf-existing',NULL,'Existing',0,0,'2026-01-01','2026-01-01')`,
		`INSERT INTO bookshelf_entries VALUES ('shelf-existing','book-1',0,'2026-01-01')`,
	}
	for _, statement := range statements {
		if _, err := db.Exec(statement); err != nil {
			db.Close()
			t.Fatal(err)
		}
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}
	return databasePath, textPath
}

func stringsOf(value byte, count int) string {
	bytes := make([]byte, count)
	for i := range bytes {
		bytes[i] = value
	}
	return string(bytes)
}
