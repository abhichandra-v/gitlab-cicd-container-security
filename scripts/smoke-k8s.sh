#!/usr/bin/env bash
# Port-forwards the Service and runs scripts/smoke.sh through it, so the test
# goes Service -> Endpoints -> Pod like in-cluster traffic would.
#
#   scripts/smoke-k8s.sh [namespace]     default orders-dev
set -euo pipefail

cd "$(dirname "$0")/.."
NS="${1:-orders-dev}"
PORT="${SMOKE_PORT:-18080}"
log="$(mktemp)"

kubectl -n "$NS" port-forward service/orders-api "$PORT:80" >"$log" 2>&1 &
pf=$!
trap 'kill "$pf" 2>/dev/null || true; rm -f "$log"' EXIT

for _ in $(seq 1 50); do
  if curl -fsS -o /dev/null "http://127.0.0.1:$PORT/healthz" 2>/dev/null; then break; fi
  if ! kill -0 "$pf" 2>/dev/null; then
    echo "port-forward exited:"
    cat "$log"
    exit 1
  fi
  sleep 0.2
done

bash scripts/smoke.sh "http://127.0.0.1:$PORT"
