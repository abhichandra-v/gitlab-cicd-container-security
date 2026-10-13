#!/bin/sh
# Downloads a file and refuses to keep it unless its SHA-256 matches.
#
#   scripts/fetch-verified.sh <url> <sha256> <output-path>
#
# Used by pipeline jobs that need a release binary (kind, kubectl) in an image
# that does not ship it. POSIX sh. Prefers curl; falls back to busybox wget
# with retries (wget tries one address per attempt, and a CDN node can refuse
# a connection).
set -eu

url="${1:?usage: fetch-verified.sh <url> <sha256> <output-path>}"
sha="${2:?missing sha256}"
out="${3:?missing output path}"

if command -v curl >/dev/null 2>&1; then
  # curl falls back to the next address when one refuses the connection.
  curl -fsSL --retry 4 --retry-delay 3 --retry-all-errors -o "$out" "$url"
else
  attempt=1
  until wget -q -O "$out" "$url"; do
    if [ "$attempt" -ge 5 ]; then
      echo "fetch-verified: download failed after $attempt attempts: $url" >&2
      rm -f "$out"
      exit 1
    fi
    echo "fetch-verified: attempt $attempt failed, retrying" >&2
    attempt=$((attempt + 1))
    sleep 3
  done
fi

if ! echo "$sha  $out" | sha256sum -c - >/dev/null; then
  echo "fetch-verified: CHECKSUM MISMATCH for $url" >&2
  echo "  expected $sha" >&2
  echo "  got      $(sha256sum "$out" | cut -d' ' -f1)" >&2
  rm -f "$out"
  exit 1
fi
echo "fetch-verified: ok $(basename "$out") sha256=$sha"
