package main

import (
	"bytes"
	"context"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"
)

// syncBuffer is a bytes.Buffer safe to share between the server goroutine
// and the test.
type syncBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *syncBuffer) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *syncBuffer) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}

func testEnv(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestRunServesAndShutsDownGracefully(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var logs syncBuffer
	addrCh := make(chan string, 1)
	done := make(chan error, 1)
	go func() {
		done <- run(ctx, testEnv(map[string]string{"PORT": "0", "SHUTDOWN_TIMEOUT": "5s"}), &logs, addrCh)
	}()

	var addr string
	select {
	case addr = <-addrCh:
	case err := <-done:
		t.Fatalf("run exited before listening: %v", err)
	case <-time.After(5 * time.Second):
		t.Fatal("server did not start listening")
	}
	_, port, err := net.SplitHostPort(addr)
	if err != nil {
		t.Fatalf("bad address %q: %v", addr, err)
	}
	base := "http://127.0.0.1:" + port

	// No keep-alives: an unused pooled connection would sit in the server's
	// "new" state, which Shutdown only reaps after five seconds.
	client := &http.Client{Transport: &http.Transport{DisableKeepAlives: true}, Timeout: 5 * time.Second}

	post, err := client.Post(base+"/orders", "application/json", strings.NewReader(`{"customer":"alice","item":"widget","quantity":2}`))
	if err != nil {
		t.Fatalf("POST /orders: %v", err)
	}
	_, _ = io.Copy(io.Discard, post.Body)
	_ = post.Body.Close()
	if post.StatusCode != http.StatusCreated {
		t.Fatalf("POST /orders = %d, want 201", post.StatusCode)
	}

	for _, path := range []string{post.Header.Get("Location"), "/orders", "/healthz", "/readyz"} {
		resp, err := client.Get(base + path)
		if err != nil {
			t.Fatalf("GET %s: %v", path, err)
		}
		_ = resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			t.Errorf("GET %s = %d, want 200", path, resp.StatusCode)
		}
	}

	cancel() // what SIGTERM does in main

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("run returned %v, want nil after graceful shutdown", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("server did not shut down")
	}

	for _, want := range []string{"server started", "shutdown started", "server stopped"} {
		if !strings.Contains(logs.String(), want) {
			t.Errorf("logs missing %q:\n%s", want, logs.String())
		}
	}
	if _, err := client.Get(base + "/healthz"); err == nil {
		t.Error("server still accepting connections after shutdown")
	}
}

func TestRunFailsFast(t *testing.T) {
	// Hold a port so the "address in use" case is real.
	ln, err := net.Listen("tcp", ":0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	defer ln.Close()
	_, busyPort, _ := net.SplitHostPort(ln.Addr().String())

	tests := []struct {
		name string
		env  map[string]string
	}{
		{"invalid config", map[string]string{"PORT": "not-a-port"}},
		{"port in use", map[string]string{"PORT": busyPort}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := run(context.Background(), testEnv(tt.env), io.Discard, nil); err == nil {
				t.Error("run returned nil, want an error")
			}
		})
	}
}
