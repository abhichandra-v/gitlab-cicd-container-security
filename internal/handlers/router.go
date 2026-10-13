package handlers

import (
	"log/slog"
	"net/http"
	"time"
)

// New returns the API handler.
func New(s OrderStore, log *slog.Logger) http.Handler {
	a := &api{store: s, log: log}

	mux := http.NewServeMux()
	mux.HandleFunc("POST /orders", a.createOrder)
	mux.HandleFunc("GET /orders", a.listOrders)
	mux.HandleFunc("GET /orders/{id}", a.getOrder)

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

// logRequests writes one structured line per request.
func logRequests(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		log.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	})
}
