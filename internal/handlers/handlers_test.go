package handlers

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/abhichandra-v/gitlab-cicd-container-security/internal/store"
)

func newTestHandler(t *testing.T, s OrderStore) (http.Handler, *atomic.Bool, *bytes.Buffer) {
	t.Helper()
	var logs bytes.Buffer
	log := slog.New(slog.NewJSONHandler(&logs, &slog.HandlerOptions{Level: slog.LevelDebug}))
	ready := &atomic.Bool{}
	ready.Store(true)
	return New(s, log, ready), ready, &logs
}

func do(h http.Handler, method, path, body string) *httptest.ResponseRecorder {
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(method, path, r))
	return rec
}

func errorMessage(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("response is not a JSON object: %v (%q)", err, rec.Body.String())
	}
	return body["error"]
}

func TestCreateOrder(t *testing.T) {
	long := strings.Repeat("x", maxFieldLen+1)

	tests := []struct {
		name       string
		body       string
		wantStatus int
		wantError  string
	}{
		{"valid", `{"customer":"alice","item":"widget","quantity":2}`, http.StatusCreated, ""},
		{"valid with surrounding space", `{"customer":"  alice ","item":" widget ","quantity":1}`, http.StatusCreated, ""},
		{"max quantity", `{"customer":"alice","item":"widget","quantity":10000}`, http.StatusCreated, ""},
		{"empty body", ``, http.StatusBadRequest, "invalid JSON body"},
		{"malformed json", `{"customer":`, http.StatusBadRequest, "invalid JSON body"},
		{"wrong type", `{"customer":"alice","item":"widget","quantity":"two"}`, http.StatusBadRequest, "invalid JSON body"},
		{"unknown field", `{"customer":"alice","item":"widget","quantity":1,"admin":true}`, http.StatusBadRequest, "invalid JSON body"},
		{"missing customer", `{"item":"widget","quantity":1}`, http.StatusUnprocessableEntity, "customer is required"},
		{"blank customer", `{"customer":"   ","item":"widget","quantity":1}`, http.StatusUnprocessableEntity, "customer is required"},
		{"long customer", `{"customer":"` + long + `","item":"widget","quantity":1}`, http.StatusUnprocessableEntity, "customer is too long"},
		{"missing item", `{"customer":"alice","quantity":1}`, http.StatusUnprocessableEntity, "item is required"},
		{"long item", `{"customer":"alice","item":"` + long + `","quantity":1}`, http.StatusUnprocessableEntity, "item is too long"},
		{"zero quantity", `{"customer":"alice","item":"widget","quantity":0}`, http.StatusUnprocessableEntity, "quantity must be between 1 and 10000"},
		{"negative quantity", `{"customer":"alice","item":"widget","quantity":-1}`, http.StatusUnprocessableEntity, "quantity must be between 1 and 10000"},
		{"quantity too large", `{"customer":"alice","item":"widget","quantity":10001}`, http.StatusUnprocessableEntity, "quantity must be between 1 and 10000"},
		{"body too large", `{"customer":"` + strings.Repeat("x", maxBodyBytes) + `"}`, http.StatusRequestEntityTooLarge, "request body too large"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			h, _, _ := newTestHandler(t, store.New(10))
			rec := do(h, http.MethodPost, "/orders", tt.body)

			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d (body %q)", rec.Code, tt.wantStatus, rec.Body.String())
			}
			if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
				t.Errorf("Content-Type = %q, want application/json", ct)
			}
			if tt.wantError != "" {
				if got := errorMessage(t, rec); got != tt.wantError {
					t.Errorf("error = %q, want %q", got, tt.wantError)
				}
				return
			}

			var o store.Order
			if err := json.Unmarshal(rec.Body.Bytes(), &o); err != nil {
				t.Fatalf("decode order: %v", err)
			}
			if o.ID == "" || o.CreatedAt.IsZero() {
				t.Errorf("order missing server-set fields: %+v", o)
			}
			if o.Customer != "alice" || o.Item != "widget" {
				t.Errorf("order = %+v, want trimmed customer alice and item widget", o)
			}
			if loc := rec.Header().Get("Location"); loc != "/orders/"+o.ID {
				t.Errorf("Location = %q, want %q", loc, "/orders/"+o.ID)
			}
		})
	}
}

func TestGetOrder(t *testing.T) {
	s := store.New(10)
	existing, err := s.Create("alice", "widget", 3)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	h, _, _ := newTestHandler(t, s)

	tests := []struct {
		name       string
		id         string
		wantStatus int
	}{
		{"existing", existing.ID, http.StatusOK},
		{"unknown", "0000000000000000", http.StatusNotFound},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			rec := do(h, http.MethodGet, "/orders/"+tt.id, "")
			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d", rec.Code, tt.wantStatus)
			}
			if tt.wantStatus != http.StatusOK {
				if got := errorMessage(t, rec); got != "order not found" {
					t.Errorf("error = %q, want %q", got, "order not found")
				}
				return
			}
			var o store.Order
			if err := json.Unmarshal(rec.Body.Bytes(), &o); err != nil {
				t.Fatalf("decode order: %v", err)
			}
			if o != existing {
				t.Errorf("order = %+v, want %+v", o, existing)
			}
		})
	}
}

func TestListOrders(t *testing.T) {
	tests := []struct {
		name  string
		count int
	}{
		{"empty", 0},
		{"one", 1},
		{"several", 3},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := store.New(10)
			for i := 0; i < tt.count; i++ {
				if _, err := s.Create("alice", "widget", i+1); err != nil {
					t.Fatalf("Create: %v", err)
				}
			}
			h, _, _ := newTestHandler(t, s)

			rec := do(h, http.MethodGet, "/orders", "")
			if rec.Code != http.StatusOK {
				t.Fatalf("status = %d, want 200", rec.Code)
			}
			// An empty list must be "[]", not "null".
			if tt.count == 0 && strings.TrimSpace(rec.Body.String()) != "[]" {
				t.Errorf("body = %q, want []", rec.Body.String())
			}
			var got []store.Order
			if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
				t.Fatalf("decode list: %v", err)
			}
			if len(got) != tt.count {
				t.Errorf("got %d orders, want %d", len(got), tt.count)
			}
		})
	}
}

func TestRouting(t *testing.T) {
	h, _, _ := newTestHandler(t, store.New(10))

	tests := []struct {
		name       string
		method     string
		path       string
		wantStatus int
	}{
		{"delete orders not allowed", http.MethodDelete, "/orders", http.StatusMethodNotAllowed},
		{"put order not allowed", http.MethodPut, "/orders/abc", http.StatusMethodNotAllowed},
		{"post healthz not allowed", http.MethodPost, "/healthz", http.StatusMethodNotAllowed},
		{"unknown path", http.MethodGet, "/nope", http.StatusNotFound},
		{"root", http.MethodGet, "/", http.StatusNotFound},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if rec := do(h, tt.method, tt.path, ""); rec.Code != tt.wantStatus {
				t.Errorf("%s %s = %d, want %d", tt.method, tt.path, rec.Code, tt.wantStatus)
			}
		})
	}
}

func TestHealthAndReadiness(t *testing.T) {
	tests := []struct {
		name       string
		path       string
		ready      bool
		wantStatus int
		wantBody   string
	}{
		{"healthz when ready", "/healthz", true, http.StatusOK, "ok"},
		{"healthz when not ready", "/healthz", false, http.StatusOK, "ok"},
		{"readyz when ready", "/readyz", true, http.StatusOK, "ready"},
		{"readyz when not ready", "/readyz", false, http.StatusServiceUnavailable, "not ready"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			h, ready, _ := newTestHandler(t, store.New(1))
			ready.Store(tt.ready)

			rec := do(h, http.MethodGet, tt.path, "")
			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d", rec.Code, tt.wantStatus)
			}
			var body map[string]string
			if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
				t.Fatalf("decode: %v", err)
			}
			if body["status"] != tt.wantBody {
				t.Errorf("status field = %q, want %q", body["status"], tt.wantBody)
			}
		})
	}
}

// failingStore lets tests force the store error paths.
type failingStore struct {
	createErr error
	getErr    error
}

func (f failingStore) Create(string, string, int) (store.Order, error) {
	return store.Order{}, f.createErr
}
func (f failingStore) Get(string) (store.Order, error) { return store.Order{}, f.getErr }
func (f failingStore) List() []store.Order             { return []store.Order{} }

func TestStoreErrors(t *testing.T) {
	boom := errors.New("boom")
	valid := `{"customer":"alice","item":"widget","quantity":1}`

	tests := []struct {
		name       string
		store      failingStore
		method     string
		path       string
		body       string
		wantStatus int
		wantError  string
	}{
		{"create when full", failingStore{createErr: store.ErrFull}, http.MethodPost, "/orders", valid, http.StatusInsufficientStorage, "order store is full"},
		{"create internal error", failingStore{createErr: boom}, http.MethodPost, "/orders", valid, http.StatusInternalServerError, "internal error"},
		{"get internal error", failingStore{getErr: boom}, http.MethodGet, "/orders/abc", "", http.StatusInternalServerError, "internal error"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			h, _, logs := newTestHandler(t, tt.store)
			rec := do(h, tt.method, tt.path, tt.body)

			if rec.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d", rec.Code, tt.wantStatus)
			}
			if got := errorMessage(t, rec); got != tt.wantError {
				t.Errorf("error = %q, want %q", got, tt.wantError)
			}
			// Internal error details go to the log, never to the client.
			if strings.Contains(rec.Body.String(), "boom") {
				t.Error("response leaked the internal error text")
			}
			if tt.wantStatus == http.StatusInternalServerError && !strings.Contains(logs.String(), "boom") {
				t.Error("internal error was not logged")
			}
		})
	}
}

func TestRequestLogging(t *testing.T) {
	tests := []struct {
		name      string
		path      string
		wantLevel string
		wantCode  float64
	}{
		{"api request at info", "/orders", "INFO", 200},
		{"not found at info", "/nope", "INFO", 404},
		{"healthz at debug", "/healthz", "DEBUG", 200},
		{"readyz at debug", "/readyz", "DEBUG", 200},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			h, _, logs := newTestHandler(t, store.New(1))
			do(h, http.MethodGet, tt.path, "")

			var entry map[string]any
			if err := json.Unmarshal(logs.Bytes(), &entry); err != nil {
				t.Fatalf("log line is not JSON: %v (%q)", err, logs.String())
			}
			if entry["level"] != tt.wantLevel {
				t.Errorf("level = %v, want %v", entry["level"], tt.wantLevel)
			}
			if entry["path"] != tt.path || entry["method"] != "GET" || entry["status"] != tt.wantCode {
				t.Errorf("log entry = %v", entry)
			}
		})
	}
}
