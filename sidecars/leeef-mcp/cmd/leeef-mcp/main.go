package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	leeefserver "github.com/leeef-reader/leeef-mcp/internal/server"
)

type readyMessage struct {
	Type     string `json:"type"`
	Endpoint string `json:"endpoint"`
	PID      int    `json:"pid"`
}

func main() {
	listenAddress := flag.String("listen", "127.0.0.1:0", "loopback listen address")
	databasePath := flag.String("database", "", "path to the Leeef SQLite database")
	deviceID := flag.String("device-id", "mcp-sidecar", "device ID recorded in MCP sync operations")
	writable := flag.Bool("writable", false, "enable confirmed MCP write tools")
	flag.Parse()

	token := os.Getenv("LEEEF_MCP_TOKEN")
	server, err := leeefserver.New(leeefserver.Config{
		Token:        token,
		DatabasePath: *databasePath,
		DeviceID:     *deviceID,
		Writable:     *writable,
	})
	if err != nil {
		log.Fatal(err)
	}
	defer server.Close()

	listener, err := net.Listen("tcp", *listenAddress)
	if err != nil {
		log.Fatal(err)
	}
	if !listener.Addr().(*net.TCPAddr).IP.IsLoopback() {
		log.Fatal("leeef-mcp must listen on a loopback address")
	}

	ready := readyMessage{
		Type:     "ready",
		Endpoint: fmt.Sprintf("http://%s/mcp", listener.Addr().String()),
		PID:      os.Getpid(),
	}
	if err := json.NewEncoder(os.Stdout).Encode(ready); err != nil {
		log.Fatal(err)
	}

	httpServer := &http.Server{Handler: server}
	go func() {
		if err := httpServer.Serve(listener); err != nil && err != http.ErrServerClosed {
			log.Printf("serve MCP: %v", err)
		}
	}()

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	<-signals
	if err := httpServer.Close(); err != nil {
		log.Printf("close MCP server: %v", err)
	}
}
