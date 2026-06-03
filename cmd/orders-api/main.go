// Command orders-api serves the orders HTTP API.
package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/abhichandra-v/orders-api-pipeline/internal/config"
	"github.com/abhichandra-v/orders-api-pipeline/internal/handlers"
	"github.com/abhichandra-v/orders-api-pipeline/internal/store"
)

// version is set at build time with -ldflags "-X main.version=...".
var version = "dev"

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()

	if err := run(ctx, os.Getenv, os.Stdout, nil); err != nil {
		fmt.Fprintln(os.Stderr, "orders-api:", err)
		os.Exit(1)
	}
}

// run starts the server and blocks until ctx is cancelled, then shuts down
// gracefully. If addrCh is not nil, the bound address is sent on it once the
// listener is open (tests use this with PORT=0).
func run(ctx context.Context, getenv func(string) string, out io.Writer, addrCh chan<- string) error {
	cfg, err := config.Load(getenv)
	if err != nil {
		return err
	}

	log := slog.New(slog.NewJSONHandler(out, &slog.HandlerOptions{Level: cfg.LogLevel}))

	var ready atomic.Bool
	srv := &http.Server{
		Handler:           handlers.New(store.New(cfg.MaxOrders), log, &ready),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      10 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	ln, err := net.Listen("tcp", ":"+strconv.Itoa(cfg.Port))
	if err != nil {
		return err
	}
	if addrCh != nil {
		addrCh <- ln.Addr().String()
	}

	serveErr := make(chan error, 1)
	go func() { serveErr <- srv.Serve(ln) }()

	ready.Store(true)
	log.Info("server started", "addr", ln.Addr().String(), "version", version)

	select {
	case err := <-serveErr:
		return err
	case <-ctx.Done():
	}

	ready.Store(false)
	log.Info("shutdown started", "timeout", cfg.ShutdownTimeout.String())

	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("shutdown: %w", err)
	}
	if err := <-serveErr; err != nil && !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	log.Info("server stopped")
	return nil
}
