#!/usr/bin/env bash
# Runs a command inside the toolbox image (build/toolbox/Dockerfile) with the
# repo mounted at /src and the host Docker socket available. Needs only Docker.
#
#   scripts/toolbox.sh make test
#   scripts/toolbox.sh            # interactive shell
set -euo pipefail

IMAGE="${TOOLBOX_IMAGE:-orders-api-toolbox:local}"
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# Git Bash on Windows: hand Docker a Windows path and stop MSYS rewriting
# container paths such as /src.
if command -v cygpath >/dev/null 2>&1; then
  root="$(cygpath -m "$root")"
  export MSYS_NO_PATHCONV=1
fi

if ! docker image inspect "$IMAGE" >/dev/null 2>&1 || [ "${TOOLBOX_REBUILD:-0}" = 1 ]; then
  docker build -t "$IMAGE" "$root/build/toolbox"
fi

# Optional flags are collected here ("${opts[@]}" on an empty array is an
# error under `set -u` in older bash, so the array always has one element).
opts=(--rm)
if [ -t 0 ] && [ -t 1 ]; then opts+=(-it); fi
# If a kind cluster exists, start on its network so kubectl can reach the
# API server by container name (see scripts/kind-up.sh).
if docker network inspect kind >/dev/null 2>&1; then opts+=(--network kind); fi
if [ "$#" -eq 0 ]; then set -- bash; fi

exec docker run "${opts[@]}" \
  -v "$root:/src" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v orders-api-gocache:/root/.cache \
  -v orders-api-gomod:/go/pkg/mod \
  -v orders-api-kube:/root/.kube \
  -e IN_TOOLBOX=1 \
  --add-host host.docker.internal:host-gateway \
  -w /src \
  "$IMAGE" "$@"
