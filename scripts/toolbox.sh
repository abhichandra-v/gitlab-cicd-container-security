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

tty=()
if [ -t 0 ] && [ -t 1 ]; then tty=(-it); fi
if [ "$#" -eq 0 ]; then set -- bash; fi

exec docker run --rm "${tty[@]}" \
  -v "$root:/src" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v orders-api-gocache:/root/.cache \
  -v orders-api-gomod:/go/pkg/mod \
  -e IN_TOOLBOX=1 \
  --add-host host.docker.internal:host-gateway \
  -w /src \
  "$IMAGE" "$@"
