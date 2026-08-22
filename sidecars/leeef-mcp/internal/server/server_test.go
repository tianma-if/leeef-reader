package server

import (
	"bytes"
	"database/sql"
	"encoding/json"
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
