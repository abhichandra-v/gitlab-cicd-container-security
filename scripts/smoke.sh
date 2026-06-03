#!/usr/bin/env bash
# Black-box smoke test against a running orders-api.
#   scripts/smoke.sh [base-url]        default http://127.0.0.1:8080
# Exits non-zero on the first failed check. Needs only bash and curl.
set -euo pipefail

BASE="${1:-${BASE_URL:-http://127.0.0.1:8080}}"
body="$(mktemp)"
trap 'rm -f "$body"' EXIT

# request METHOD PATH [JSON]  -> prints the HTTP status, body goes to $body
request() {
  local method="$1" path="$2" data="${3:-}"
  local args=(-sS -o "$body" -w '%{http_code}' --max-time 10 -X "$method")
  if [ -n "$data" ]; then args+=(-H 'Content-Type: application/json' -d "$data"); fi
  curl "${args[@]}" "$BASE$path"
}

# expect NAME WANT_STATUS METHOD PATH [JSON]
expect() {
  local name="$1" want="$2" got
  shift 2
  got="$(request "$@")"
  if [ "$got" != "$want" ]; then
    printf 'FAIL  %-34s got %s, want %s: %s\n' "$name" "$got" "$want" "$(cat "$body")"
    exit 1
  fi
  printf 'ok    %-34s %s\n' "$name" "$got"
}

printf 'smoke test against %s\n' "$BASE"

expect "GET /healthz" 200 GET /healthz
expect "GET /readyz" 200 GET /readyz

expect "POST /orders" 201 POST /orders '{"customer":"smoke","item":"widget","quantity":2}'
id="$(sed -n 's/.*"id":"\([^"]*\)".*/\1/p' "$body")"
if [ -z "$id" ]; then
  printf 'FAIL  no id in create response: %s\n' "$(cat "$body")"
  exit 1
fi

expect "GET /orders/{id}" 200 GET "/orders/$id"
if ! grep -q '"customer":"smoke"' "$body"; then
  printf 'FAIL  fetched order does not match what was created: %s\n' "$(cat "$body")"
  exit 1
fi

expect "GET /orders" 200 GET /orders
if ! grep -q "\"id\":\"$id\"" "$body"; then
  printf 'FAIL  created order %s missing from list\n' "$id"
  exit 1
fi

expect "GET /orders/{unknown} is 404" 404 GET /orders/0000000000000000
expect "POST /orders invalid is 422" 422 POST /orders '{"customer":"smoke","item":"widget","quantity":0}'

printf 'smoke test passed (order %s)\n' "$id"
