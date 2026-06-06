#!/usr/bin/env bash
# Loads the image into the kind cluster, applies the dev overlay and waits
# for the rollout. Used by `make deploy` and by the deploy-test pipeline job.
#
#   scripts/deploy.sh [image]      default orders-api:local
#
# The dev overlay expects the image to be called orders-api:local, so any
# other reference is tagged to that name before loading.
set -euo pipefail

cd "$(dirname "$0")/.."
IMAGE="${1:-${IMAGE:-orders-api:local}}"
CLUSTER="${KIND_CLUSTER:-orders-api}"
NS=orders-dev
TIMEOUT="${ROLLOUT_TIMEOUT:-180s}"

if [ "$IMAGE" != orders-api:local ]; then
  docker tag "$IMAGE" orders-api:local
fi

echo "--- loading orders-api:local into kind cluster '$CLUSTER'"
bash scripts/kind-load.sh orders-api:local

echo "--- applying k8s/overlays/dev"
kubectl apply -k k8s/overlays/dev

echo "--- waiting for the rollout (timeout $TIMEOUT)"
kubectl -n "$NS" rollout status deployment/orders-api --timeout "$TIMEOUT"

echo "--- deployed"
kubectl -n "$NS" get deployment,pod,service,networkpolicy,poddisruptionbudget -o wide
