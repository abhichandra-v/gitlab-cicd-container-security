#!/bin/sh
# Writes release notes for a tag to stdout: the image to pull and the commits
# since the previous tag. POSIX sh; needs git with full history.
#
#   scripts/release-notes.sh <tag> <image-repository> <image-digest-ref>
set -eu

tag="${1:?usage: release-notes.sh <tag> <image-repository> <image-digest-ref>}"
repo="${2:?missing image repository}"
digest_ref="${3:?missing image digest reference}"

prev="$(git describe --tags --abbrev=0 "${tag}^" 2>/dev/null || true)"
if [ -n "$prev" ]; then range="${prev}..${tag}"; else range="$tag"; fi

printf '## Image\n\n'
printf '```\n%s:%s\n%s\n```\n\n' "$repo" "$tag" "$digest_ref"
printf 'The tag and the digest are the same image: the one this pipeline built,\n'
printf 'scanned and deploy-tested. Deploy by digest.\n\n'

if [ -n "$prev" ]; then
  printf '## Changes since %s\n\n' "$prev"
else
  printf '## Changes\n\n'
fi
git log --no-merges --pretty='- %s (%h)' "$range"
