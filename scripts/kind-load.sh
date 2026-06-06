#!/usr/bin/env bash
# Loads a local Docker image into the kind cluster.
#
#   scripts/kind-load.sh <image>
#
# `kind load docker-image` fails for a multi-platform image on Docker's
# containerd image store ("ctr: content digest ... not found"), because the
# archive references platforms that were never pulled. Saving only the
# daemon's own platform and loading that archive works on both image stores.
set -euo pipefail

IMAGE="${1:?usage: kind-load.sh <image>}"
CLUSTER="${KIND_CLUSTER:-orders-api}"
platform="$(docker version --format '{{.Server.Os}}/{{.Server.Arch}}')"
archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT

if docker save --platform "$platform" "$IMAGE" -o "$archive" 2>/dev/null; then
  kind load image-archive "$archive" --name "$CLUSTER"
else
  # Older Docker without `save --platform`.
  kind load docker-image "$IMAGE" --name "$CLUSTER"
fi
echo "loaded $IMAGE ($platform) into kind cluster '$CLUSTER'"
