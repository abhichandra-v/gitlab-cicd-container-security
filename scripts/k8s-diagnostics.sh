#!/usr/bin/env bash
# Collects what is needed to debug a failed deploy into a directory.
# The deploy-test job runs it on failure and uploads the directory.
#
#   scripts/k8s-diagnostics.sh [namespace] [output-dir]
set -uo pipefail

NS="${1:-orders-dev}"
OUT="${2:-diagnostics}"
mkdir -p "$OUT"

kubectl get nodes -o wide >"$OUT/nodes.txt" 2>&1
kubectl -n "$NS" get all,networkpolicy,poddisruptionbudget -o wide >"$OUT/resources.txt" 2>&1
kubectl -n "$NS" describe deployment/orders-api >"$OUT/describe-deployment.txt" 2>&1
kubectl -n "$NS" describe pods >"$OUT/describe-pods.txt" 2>&1
kubectl -n "$NS" get events --sort-by=.lastTimestamp >"$OUT/events.txt" 2>&1
kubectl -n "$NS" logs -l app.kubernetes.io/name=orders-api --all-containers --tail=200 --prefix >"$OUT/logs.txt" 2>&1
kubectl -n "$NS" logs -l app.kubernetes.io/name=orders-api --all-containers --tail=200 --prefix --previous >"$OUT/logs-previous.txt" 2>&1

echo "diagnostics written to $OUT/:"
ls -l "$OUT"
