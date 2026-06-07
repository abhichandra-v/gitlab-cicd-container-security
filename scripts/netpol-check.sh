#!/usr/bin/env bash
# Checks that the NetworkPolicies are actually enforced by the cluster's CNI,
# not just accepted by the API server:
#   1. a client in another namespace CAN reach the Service (the allow rule);
#   2. a pod inside the app namespace CANNOT make outbound connections
#      (default deny egress).
# Needs a running kind cluster with the dev overlay applied.
set -euo pipefail

NS="${1:-orders-dev}"
PROBE_IMAGE="${PROBE_IMAGE:-alpine:3.24.2@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6}"
svc_ip="$(kubectl -n "$NS" get service orders-api -o jsonpath='{.spec.clusterIP}')"

docker image inspect "$PROBE_IMAGE" >/dev/null 2>&1 || docker pull -q "$PROBE_IMAGE"
bash "$(dirname "$0")/kind-load.sh" "$PROBE_IMAGE" >/dev/null

# A probe pod that satisfies the "restricted" Pod Security Standard.
overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":65532,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"probe","image":"'"$PROBE_IMAGE"'","imagePullPolicy":"IfNotPresent","command":["wget","-q","-T","5","-O","-","http://'"$svc_ip"'/healthz"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'

probe() { # namespace -> prints wget output, returns its exit status
  local ns="$1" phase
  kubectl -n "$ns" delete pod netpol-probe --ignore-not-found >/dev/null 2>&1
  kubectl -n "$ns" run netpol-probe --image "$PROBE_IMAGE" --restart Never --overrides "$overrides" >/dev/null
  for _ in $(seq 1 40); do
    phase="$(kubectl -n "$ns" get pod netpol-probe -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    case "$phase" in Succeeded | Failed) break ;; esac
    sleep 1
  done
  kubectl -n "$ns" logs netpol-probe 2>&1 || true
  kubectl -n "$ns" delete pod netpol-probe --wait=false >/dev/null 2>&1
  [ "$phase" = Succeeded ]
}

fail=0

printf '1. from namespace "default" to http://%s/healthz (expected: allowed)\n' "$svc_ip"
if probe default; then
  printf '   ALLOWED, as expected\n'
else
  printf '   BLOCKED, but the allow rule should let this through\n'
  fail=1
fi

printf '2. from inside namespace "%s" to http://%s/healthz (expected: blocked by default-deny egress)\n' "$NS" "$svc_ip"
if probe "$NS"; then
  printf '   ALLOWED, but default-deny egress should block this\n'
  fail=1
else
  printf '   BLOCKED, as expected\n'
fi

exit "$fail"
