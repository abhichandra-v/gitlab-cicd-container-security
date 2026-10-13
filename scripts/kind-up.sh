#!/usr/bin/env bash
# Creates the kind cluster (if it does not exist) and points kubectl at it.
#
# Three places run this, and they reach the API server differently:
#   laptop          kind publishes the API on 127.0.0.1; nothing special.
#   toolbox         this script runs in a container next to the kind node, so
#                   it joins the "kind" Docker network and uses the internal
#                   kubeconfig (https://<cluster>-control-plane:6443).
#   CI (dind)       the node runs inside the docker:dind service. Set
#                   KIND_API_HOST=docker: the API server then listens on all
#                   interfaces, its certificate includes that name, and the
#                   kubeconfig is rewritten to https://docker:6443.
set -euo pipefail

CLUSTER="${KIND_CLUSTER:-orders-api}"
NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5}"
API_HOST="${KIND_API_HOST:-}"

config="$(mktemp)"
trap 'rm -f "$config"' EXIT

{
  printf 'kind: Cluster\napiVersion: kind.x-k8s.io/v1alpha4\n'
  if [ -n "$API_HOST" ]; then
    printf 'networking:\n  apiServerAddress: "0.0.0.0"\n  apiServerPort: 6443\n'
    printf 'kubeadmConfigPatches:\n  - |\n    kind: ClusterConfiguration\n    apiServer:\n      certSANs:\n        - "%s"\n        - localhost\n        - 127.0.0.1\n' "$API_HOST"
  fi
} >"$config"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "kind cluster '$CLUSTER' already exists"
else
  kind create cluster --name "$CLUSTER" --image "$NODE_IMAGE" --config "$config" --wait 180s
fi

if [ -n "$API_HOST" ]; then
  kind export kubeconfig --name "$CLUSTER"
  kubectl config set-cluster "kind-$CLUSTER" --server "https://$API_HOST:6443" >/dev/null
elif [ "${IN_TOOLBOX:-0}" = 1 ]; then
  docker network connect kind "$(hostname)" 2>/dev/null || true
  kind export kubeconfig --name "$CLUSTER" --internal
else
  kind export kubeconfig --name "$CLUSTER"
fi

kubectl cluster-info
kubectl get nodes -o wide
