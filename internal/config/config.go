// Package config reads runtime configuration from environment variables.
package config

import (
	"fmt"
	"log/slog"
	"strconv"
	"time"
)

// Config is the runtime configuration.
type Config struct {
	Port            int
	LogLevel        slog.Level
	ShutdownTimeout time.Duration
	MaxOrders       int
}

// Load builds a Config from getenv (os.Getenv in production). Unset variables
// fall back to defaults; set but invalid ones are an error.
func Load(getenv func(string) string) (Config, error) {
	cfg := Config{
		Port:            8080,
		LogLevel:        slog.LevelInfo,
		ShutdownTimeout: 10 * time.Second,
		MaxOrders:       10000,
	}

	if v := getenv("PORT"); v != "" {
		p, err := strconv.Atoi(v)
		if err != nil || p < 0 || p > 65535 {
			return Config{}, fmt.Errorf("PORT: %q is not a valid port", v)
		}
		cfg.Port = p
	}
	if v := getenv("LOG_LEVEL"); v != "" {
		if err := cfg.LogLevel.UnmarshalText([]byte(v)); err != nil {
			return Config{}, fmt.Errorf("LOG_LEVEL: %q is not one of debug, info, warn, error", v)
		}
	}
	if v := getenv("SHUTDOWN_TIMEOUT"); v != "" {
		d, err := time.ParseDuration(v)
		if err != nil || d <= 0 {
			return Config{}, fmt.Errorf("SHUTDOWN_TIMEOUT: %q is not a positive duration", v)
		}
		cfg.ShutdownTimeout = d
	}
	if v := getenv("MAX_ORDERS"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 {
			return Config{}, fmt.Errorf("MAX_ORDERS: %q is not a positive integer", v)
		}
		cfg.MaxOrders = n
	}
	return cfg, nil
}
