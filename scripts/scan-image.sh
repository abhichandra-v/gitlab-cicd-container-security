#!/bin/sh
# The image vulnerability gate. Used by the `trivy-image` pipeline job and by
# `make scan`, so both apply the same rule:
#
#   fail on any HIGH or CRITICAL vulnerability that has a fix available.
#
#   scripts/scan-image.sh <image-ref> [report-dir]
#
# POSIX sh on purpose: the Trivy image has no bash. The image is scanned once
# to JSON; the GitLab report and the table are converted from that JSON, so
# all three describe the same scan.
set -eu

image="${1:?usage: scan-image.sh <image-ref> [report-dir]}"
out="${2:-reports}"
mkdir -p "$out"

echo "scanning $image"
trivy image \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --no-progress \
  --format json \
  --output "$out/trivy-image.json" \
  "$image"

# GitLab container-scanning report, if this Trivy build ships the template.
if [ -f /contrib/gitlab.tpl ]; then
  trivy convert \
    --format template \
    --template "@/contrib/gitlab.tpl" \
    --output "$out/gl-container-scanning-report.json" \
    "$out/trivy-image.json"
fi

rc=0
trivy convert \
  --format table \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --output "$out/trivy-image.txt" \
  "$out/trivy-image.json" || rc=$?

cat "$out/trivy-image.txt"

if [ "$rc" -ne 0 ]; then
  echo
  echo "GATE FAILED: $image has HIGH or CRITICAL vulnerabilities with a fix available."
  echo "See docs/RUNBOOK.md, 'Triaging a failed scan'."
  exit "$rc"
fi
echo "GATE PASSED: no fixable HIGH or CRITICAL vulnerabilities in $image."
