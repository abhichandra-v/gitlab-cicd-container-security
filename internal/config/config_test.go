package config

import (
	"log/slog"
	"strings"
	"testing"
	"time"
)

func env(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestLoad(t *testing.T) {
	defaults := Config{Port: 8080, LogLevel: slog.LevelInfo, ShutdownTimeout: 10 * time.Second, MaxOrders: 10000}

	tests := []struct {
		name    string
		env     map[string]string
		want    Config
		wantErr string
	}{
		{name: "defaults", env: nil, want: defaults},
		{
			name: "all set",
			env:  map[string]string{"PORT": "9090", "LOG_LEVEL": "debug", "SHUTDOWN_TIMEOUT": "3s", "MAX_ORDERS": "5"},
			want: Config{Port: 9090, LogLevel: slog.LevelDebug, ShutdownTimeout: 3 * time.Second, MaxOrders: 5},
		},
		{name: "port zero picks a free port", env: map[string]string{"PORT": "0"}, want: Config{Port: 0, LogLevel: slog.LevelInfo, ShutdownTimeout: 10 * time.Second, MaxOrders: 10000}},
		{name: "log level is case-insensitive", env: map[string]string{"LOG_LEVEL": "WARN"}, want: Config{Port: 8080, LogLevel: slog.LevelWarn, ShutdownTimeout: 10 * time.Second, MaxOrders: 10000}},
		{name: "port not a number", env: map[string]string{"PORT": "http"}, wantErr: "PORT"},
		{name: "port negative", env: map[string]string{"PORT": "-1"}, wantErr: "PORT"},
		{name: "port too large", env: map[string]string{"PORT": "65536"}, wantErr: "PORT"},
		{name: "bad log level", env: map[string]string{"LOG_LEVEL": "loud"}, wantErr: "LOG_LEVEL"},
		{name: "bad shutdown timeout", env: map[string]string{"SHUTDOWN_TIMEOUT": "soon"}, wantErr: "SHUTDOWN_TIMEOUT"},
		{name: "zero shutdown timeout", env: map[string]string{"SHUTDOWN_TIMEOUT": "0s"}, wantErr: "SHUTDOWN_TIMEOUT"},
		{name: "bad max orders", env: map[string]string{"MAX_ORDERS": "many"}, wantErr: "MAX_ORDERS"},
		{name: "zero max orders", env: map[string]string{"MAX_ORDERS": "0"}, wantErr: "MAX_ORDERS"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := Load(env(tt.env))
			if tt.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
					t.Fatalf("error = %v, want one mentioning %q", err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("Load: %v", err)
			}
			if got != tt.want {
				t.Errorf("Load = %+v, want %+v", got, tt.want)
			}
		})
	}
}
