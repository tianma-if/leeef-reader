package server

import (
	"bytes"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"testing"
)

func TestRequiresBearerToken(t *testing.T) {
	server, err := New(Config{Token: "secret"})
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()

	request := httptest.NewRequest(http.MethodPost, "/mcp", bytes.NewBufferString("{}"))
	response := httptest.NewRecorder()
	server.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusUnauthorized)
	}
}

func TestHealthAndLibraryStatsTools(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "leeef library.sqlite")
	db, err := sql.Open("sqlite", databasePath)
	if err != nil {
		t.Fatal(err)
	}
	for _, statement := range []string{
		"CREATE TABLE books (is_deleted INTEGER NOT NULL)",
		"CREATE TABLE excerpts (is_deleted INTEGER NOT NULL)",
		"CREATE TABLE bookmarks (is_deleted INTEGER NOT NULL)",
		"CREATE TABLE sync_operations (applied_at TEXT)",
		"INSERT INTO books VALUES (0), (0), (1)",
		"INSERT INTO excerpts VALUES (0)",
		"INSERT INTO bookmarks VALUES (0), (1)",
		"INSERT INTO sync_operations VALUES (NULL), ('2026-08-22')",
	} {
		if _, err := db.Exec(statement); err != nil {
			t.Fatal(err)
		}
	}
	db.Close()

	server, err := New(Config{Token: "secret", DatabasePath: databasePath})
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	httpServer := httptest.NewServer(server)
	defer httpServer.Close()

	sessionID, initialize := postMCP(t, httpServer.URL, "", `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}`)
	if initialize["result"] == nil || sessionID == "" {
		t.Fatalf("initialize response = %#v, session = %q", initialize, sessionID)
	}
	postMCP(t, httpServer.URL, sessionID, `{"jsonrpc":"2.0","method":"notifications/initialized"}`)
	_, response := postMCP(t, httpServer.URL, sessionID, `{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"library_stats","arguments":{}}}`)

	result := response["result"].(map[string]any)
	structured := result["structuredContent"].(map[string]any)
	if structured["books"] != float64(2) || structured["pendingSyncOperations"] != float64(1) {
		t.Fatalf("unexpected stats: %#v", structured)
	}
}

func TestConfirmedExcerptWriteIsAtomicAndAudited(t *testing.T) {
	databasePath := filepath.Join(t.TempDir(), "leeef.sqlite")
	db, err := sql.Open("sqlite", databasePath)
	if err != nil {
		t.Fatal(err)
	}
	for _, statement := range []string{
		`CREATE TABLE books (
			id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT, media_type TEXT NOT NULL,
			is_deleted INTEGER NOT NULL, updated_at INTEGER NOT NULL)`,
		`CREATE TABLE excerpts (
			id TEXT PRIMARY KEY, book_id TEXT NOT NULL, locator TEXT NOT NULL, quote TEXT NOT NULL,
			note TEXT, color TEXT NOT NULL, is_deleted INTEGER NOT NULL,
			created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)`,
		`CREATE TABLE sync_operations (
			operation_id TEXT PRIMARY KEY, device_id TEXT NOT NULL, entity_type TEXT NOT NULL,
			entity_id TEXT NOT NULL, kind TEXT NOT NULL, payload_json TEXT,
			occurred_at INTEGER NOT NULL, applied_at INTEGER)`,
		`CREATE TABLE audit_events (
			id TEXT PRIMARY KEY, caller TEXT NOT NULL, action TEXT NOT NULL,
			parameters_json TEXT NOT NULL, result TEXT NOT NULL, occurred_at INTEGER NOT NULL)`,
		`INSERT INTO books VALUES ('book-1', 'Test Book', 'Leeef', 'application/epub+zip', 0, 1)`,
	} {
		if _, err := db.Exec(statement); err != nil {
			t.Fatal(err)
		}
	}
	db.Close()

	server, err := New(Config{
		Token: "secret", DatabasePath: databasePath, DeviceID: "mcp-device", Writable: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer server.Close()
	httpServer := httptest.NewServer(server)
	defer httpServer.Close()

	sessionID, _ := postMCP(t, httpServer.URL, "", `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}`)
	postMCP(t, httpServer.URL, sessionID, `{"jsonrpc":"2.0","method":"notifications/initialized"}`)
	_, planned := postMCP(t, httpServer.URL, sessionID, `{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"plan_create_excerpt","arguments":{"bookId":"book-1","locator":"epubcfi(/6/2)","quote":"Confirmed quote"}}}`)
	plan := toolStructured(t, planned)
	planID := plan["planId"].(string)

	_, rejected := postMCP(t, httpServer.URL, sessionID, fmt.Sprintf(`{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"apply_write","arguments":{"planId":%q,"confirmationToken":"not-confirmed"}}}`, planID))
	if rejected["result"].(map[string]any)["isError"] != true {
		t.Fatalf("unconfirmed apply was not rejected: %#v", rejected)
	}

	_, confirmed := postMCP(t, httpServer.URL, sessionID, fmt.Sprintf(`{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"confirm_write","arguments":{"planId":%q}}}`, planID))
	confirmationToken := toolStructured(t, confirmed)["confirmationToken"].(string)
	_, applied := postMCP(t, httpServer.URL, sessionID, fmt.Sprintf(`{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"apply_write","arguments":{"planId":%q,"confirmationToken":%q}}}`, planID, confirmationToken))
	if toolStructured(t, applied)["applied"] != true {
		t.Fatalf("apply response = %#v", applied)
	}

	verification, err := sql.Open("sqlite", databasePath)
	if err != nil {
		t.Fatal(err)
	}
	defer verification.Close()
	for table, want := range map[string]int{"excerpts": 1, "sync_operations": 1, "audit_events": 1} {
		var count int
		if err := verification.QueryRow("SELECT count(*) FROM " + table).Scan(&count); err != nil {
			t.Fatal(err)
		}
		if count != want {
			t.Fatalf("%s count = %d, want %d", table, count, want)
		}
	}
}

func toolStructured(t *testing.T, response map[string]any) map[string]any {
	t.Helper()
	result, ok := response["result"].(map[string]any)
	if !ok {
		t.Fatalf("missing tool result: %#v", response)
	}
	structured, ok := result["structuredContent"].(map[string]any)
	if !ok {
		t.Fatalf("missing structured content: %#v", result)
	}
	return structured
}

func postMCP(t *testing.T, endpoint, sessionID, body string) (string, map[string]any) {
	t.Helper()
	request, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewBufferString(body))
	if err != nil {
		t.Fatal(err)
	}
	request.Header.Set("Authorization", "Bearer secret")
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Accept", "application/json, text/event-stream")
	if sessionID != "" {
		request.Header.Set("Mcp-Session-Id", sessionID)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	responseBody, err := io.ReadAll(response.Body)
	if err != nil {
		t.Fatal(err)
	}
	if response.StatusCode == http.StatusAccepted || len(responseBody) == 0 {
		return response.Header.Get("Mcp-Session-Id"), map[string]any{}
	}
	var decoded map[string]any
	if err := json.Unmarshal(responseBody, &decoded); err != nil {
		t.Fatalf("decode %s: %v", responseBody, err)
	}
	return response.Header.Get("Mcp-Session-Id"), decoded
}
