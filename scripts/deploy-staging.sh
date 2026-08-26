#!/usr/bin/env bash
# Deploys one image digest to a real cluster. Run by the manual deploy-staging
# pipeline job; can also be run by hand with the same variables.
#
#   IMAGE_REF       repository@sha256:...   the exact image to deploy
#   KUBECONFIG_B64  base64 of a kubeconfig  (masked, protected CI variable)
#   NAMESPACE       default orders-staging
#   DRY_RUN=1       render the manifests that would be applied, touch nothing
#
# Without KUBECONFIG_B64 it prints a notice and exits 0: a project with no
# staging cluster still gets a green pipeline. If the rollout fails, it rolls
# back to the previous revision and exits non-zero.
set -euo pipefail

cd "$(dirname "$0")/.."
NAMESPACE="${NAMESPACE:-orders-staging}"
TIMEOUT="${ROLLOUT_TIMEOUT:-180s}"

if [ "${DRY_RUN:-0}" != 1 ] && [ -z "${KUBECONFIG_B64:-}" ]; then
  echo "KUBECONFIG_B64 is not set (or this ref is not protected)."
  echo "Nothing was deployed. To enable this job, see docs/SETUP-GITLAB.md, step 5."
  exit 0
fi

: "${IMAGE_REF:?IMAGE_REF (repository@sha256:...) is required}"
case "$IMAGE_REF" in
  *@sha256:*) ;;
  *) echo "IMAGE_REF must be a digest reference, got: $IMAGE_REF" >&2; exit 1 ;;
esac

work="$(mktemp -d)"
if [ "${DRY_RUN:-0}" != 1 ]; then
  # The kubeconfig never touches the project directory or the job log.
  umask 077
  printf '%s' "$KUBECONFIG_B64" | base64 -d >"$work/kubeconfig"
  export KUBECONFIG="$work/kubeconfig"
fi

# A throwaway overlay on top of prod: same manifests, this namespace, and the
# image pinned to the digest the pipeline built and scanned.
overlay="k8s/overlays/.staging-$$"
trap 'rm -rf "$work" "$overlay"' EXIT
mkdir -p "$overlay"
cat >"$overlay/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: $NAMESPACE
resources:
  - ../prod
images:
  - name: registry.gitlab.com/abhichandra-v/gitlab-cicd-container-security
    newName: ${IMAGE_REF%@*}
    digest: ${IMAGE_REF#*@}
EOF

if [ "${DRY_RUN:-0}" = 1 ]; then
  kubectl kustomize "$overlay"
  exit 0
fi

echo "--- deploying $IMAGE_REF to namespace $NAMESPACE"
kubectl apply -k "$overlay"

echo "--- waiting for the rollout (timeout $TIMEOUT)"
if ! kubectl -n "$NAMESPACE" rollout status deployment/orders-api --timeout "$TIMEOUT"; then
  echo "--- ROLLOUT FAILED: collecting state, then rolling back"
  kubectl -n "$NAMESPACE" get pods -o wide || true
  kubectl -n "$NAMESPACE" describe deployment/orders-api || true
  kubectl -n "$NAMESPACE" logs -l app.kubernetes.io/name=orders-api --tail=50 --prefix || true
  if kubectl -n "$NAMESPACE" rollout undo deployment/orders-api; then
    kubectl -n "$NAMESPACE" rollout status deployment/orders-api --timeout "$TIMEOUT" || true
  else
    echo "Nothing to roll back to (first deploy). The failed deployment is left in place for inspection."
  fi
  exit 1
fi

echo "--- deployed"
kubectl -n "$NAMESPACE" get deployment/orders-api -o wide
echo "rollback, if needed: kubectl -n $NAMESPACE rollout undo deployment/orders-api"
