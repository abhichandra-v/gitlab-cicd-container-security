package handlers

import (
	"net/http"
	"sync/atomic"
)

// healthz reports that the process is alive. It never depends on anything
// else, so a failing dependency cannot cause a restart loop.
func healthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// readyz reports whether the server should receive traffic. It turns false
// when shutdown starts, so load balancers drain the pod before it exits.
func readyz(ready *atomic.Bool) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		if !ready.Load() {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not ready"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
	}
}
