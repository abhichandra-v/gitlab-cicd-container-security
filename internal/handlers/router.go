package handlers

import (
	"log/slog"
	"net/http"
	"sync/atomic"
	"time"
)

// New returns the API handler. ready controls the /readyz response.
func New(s OrderStore, log *slog.Logger, ready *atomic.Bool) http.Handler {
	a := &api{store: s, log: log}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /orders", a.createOrder)
	mux.HandleFunc("GET /orders", a.listOrders)
	mux.HandleFunc("GET /orders/{id}", a.getOrder)
	mux.HandleFunc("GET /healthz", healthz)
	mux.HandleFunc("GET /readyz", readyz(ready))

	return logRequests(log, mux)
}

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// logRequests writes one structured line per request. Probe requests are
// logged at debug level so they do not drown out real traffic.
func logRequests(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		level := slog.LevelInfo
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			level = slog.LevelDebug
		}
		log.Log(r.Context(), level, "request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	})
}
