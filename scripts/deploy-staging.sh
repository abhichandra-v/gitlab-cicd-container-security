#!/usr/bin/env bash
# Deploys one image digest to a real cluster through the prod overlay. Used by
# the manual deploy-staging job and by the deploy-test-k8s job (which passes a
# throwaway NAMESPACE); can also be run by hand with the same variables.
#
#   IMAGE_REF       repository@sha256:...   the exact image to deploy
#   NAMESPACE       default orders-staging
#   DRY_RUN=1       render the manifests that would be applied, touch nothing
#
# Cluster access, first match wins:
#   KUBE_CONTEXT    a context in the KUBECONFIG GitLab provides when a GitLab
#                   agent for Kubernetes is authorized for this project
#                   (for example "ai-lab/orders-api-pipeline:ai-k8s-agent")
#   KUBECONFIG_B64  base64 of a kubeconfig (masked, protected CI variable)
# With neither, it prints a notice and exits 0: a project with no cluster
# still gets a green pipeline.
#
# Registry pull credentials for a private registry, first match wins:
#   CI_DEPLOY_USER / CI_DEPLOY_PASSWORD     set by GitLab when the project has
#                                           a deploy token named
#                                           gitlab-deploy-token (read_registry)
#   REGISTRY_PULL_USER / REGISTRY_PULL_PASSWORD
# They become an imagePullSecret on the ServiceAccount. Without any, the
# cluster must be able to pull the image on its own.
#
# If the rollout fails, it rolls back to the previous revision and exits
# non-zero.
set -euo pipefail

cd "$(dirname "$0")/.."
NAMESPACE="${NAMESPACE:-orders-staging}"
TIMEOUT="${ROLLOUT_TIMEOUT:-180s}"

work="$(mktemp -d)"
overlay="k8s/overlays/.staging-$$"
trap 'rm -rf "$work" "$overlay"' EXIT

access=""
if [ "${DRY_RUN:-0}" = 1 ]; then
  access="none (dry run)"
elif [ -n "${KUBE_CONTEXT:-}" ] && kubectl config get-contexts "$KUBE_CONTEXT" >/dev/null 2>&1; then
  kubectl config use-context "$KUBE_CONTEXT" >/dev/null
  access="GitLab agent context $KUBE_CONTEXT"
elif [ -n "${KUBECONFIG_B64:-}" ]; then
  # The kubeconfig never touches the project directory or the job log.
  umask 077
  printf '%s' "$KUBECONFIG_B64" | base64 -d >"$work/kubeconfig"
  umask 022
  export KUBECONFIG="$work/kubeconfig"
  access="KUBECONFIG_B64"
else
  echo "No cluster access: no GitLab agent context${KUBE_CONTEXT:+ named $KUBE_CONTEXT} and KUBECONFIG_B64 is not set."
  echo "Nothing was deployed. To enable this job, see docs/SETUP-GITLAB.md, step 5."
  exit 0
fi

: "${IMAGE_REF:?IMAGE_REF (repository@sha256:...) is required}"
case "$IMAGE_REF" in
  *@sha256:*) ;;
  *) echo "IMAGE_REF must be a digest reference, got: $IMAGE_REF" >&2; exit 1 ;;
esac

pull_user="${CI_DEPLOY_USER:-${REGISTRY_PULL_USER:-}}"
pull_pass="${CI_DEPLOY_PASSWORD:-${REGISTRY_PULL_PASSWORD:-}}"

# A throwaway overlay on top of prod: same manifests, this namespace, the
# image pinned to the digest the pipeline built and scanned, and (if there
# are pull credentials) the pull secret on the ServiceAccount.
mkdir -p "$overlay"
{
  printf 'apiVersion: kustomize.config.k8s.io/v1beta1\nkind: Kustomization\n'
  printf 'namespace: %s\nresources:\n  - ../prod\n' "$NAMESPACE"
  printf 'images:\n  - name: registry.gitlab.com/abhichandra-v/gitlab-cicd-container-security\n'
  printf '    newName: %s\n    digest: %s\n' "${IMAGE_REF%@*}" "${IMAGE_REF#*@}"
  if [ -n "$pull_user" ]; then
    printf 'patches:\n  - target:\n      kind: ServiceAccount\n      name: orders-api\n'
    printf '    patch: |-\n      - op: add\n        path: /imagePullSecrets\n        value:\n          - name: registry-pull\n'
  fi
} >"$overlay/kustomization.yaml"

if [ "${DRY_RUN:-0}" = 1 ]; then
  kubectl kustomize "$overlay"
  exit 0
fi

echo "--- cluster access: $access"
echo "--- deploying $IMAGE_REF to namespace $NAMESPACE"

# The namespace and pull secret must exist before the pods are created.
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
if [ -n "$pull_user" ]; then
  registry="${IMAGE_REF%%/*}"
  kubectl -n "$NAMESPACE" create secret docker-registry registry-pull \
    --docker-server "$registry" --docker-username "$pull_user" --docker-password "$pull_pass" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "pull secret registry-pull set for $registry (user $pull_user)"
fi

kubectl apply -k "$overlay"

echo "--- waiting for the rollout (timeout $TIMEOUT)"
if ! kubectl -n "$NAMESPACE" rollout status deployment/orders-api --timeout "$TIMEOUT"; then
  echo "--- ROLLOUT FAILED: collecting state, then rolling back"
  kubectl -n "$NAMESPACE" get pods -o wide || true
  kubectl -n "$NAMESPACE" describe deployment/orders-api || true
  kubectl -n "$NAMESPACE" get events --sort-by=.lastTimestamp | tail -n 20 || true
  kubectl -n "$NAMESPACE" logs -l app.kubernetes.io/name=orders-api --tail=50 --prefix || true
  if kubectl -n "$NAMESPACE" rollout undo deployment/orders-api; then
    kubectl -n "$NAMESPACE" rollout status deployment/orders-api --timeout "$TIMEOUT" || true
  else
    echo "Nothing to roll back to (first deploy). The failed deployment is left in place for inspection."
  fi
  exit 1
fi

echo "--- deployed"
kubectl -n "$NAMESPACE" get deployment,pod,service,networkpolicy,poddisruptionbudget -o wide
echo "rollback, if needed: kubectl -n $NAMESPACE rollout undo deployment/orders-api"
