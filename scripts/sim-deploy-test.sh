#!/usr/bin/env bash
# Rehearses the deploy-test pipeline job on a workstation: a real docker:dind
# service with TLS, a docker:cli job container next to it, and the same
# commands the job runs. It answers one question before pushing: does
# kind-inside-dind work with this repo's scripts?
#
# Differences from the real job, both unavoidable without a registry:
#   - the image is built inside the dind daemon instead of pulled by digest;
#   - GitLab's runner, cache and artifact handling are not involved.
#
# Needs only Docker on the host. Run from the host, not from the toolbox.
set -euo pipefail

root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
if command -v cygpath >/dev/null 2>&1; then
  root="$(cygpath -m "$root")"
  export MSYS_NO_PATHCONV=1
fi

# Same pins as .gitlab-ci.yml.
ci_var() { sed -n "s/^  $1: \"\(.*\)\"\$/\1/p" "$root/.gitlab-ci.yml"; }
DOCKER_IMAGE="$(ci_var DOCKER_IMAGE)"
DIND_IMAGE="$(ci_var DIND_IMAGE)"
KIND_VERSION="$(ci_var KIND_VERSION)"
KIND_SHA256="$(ci_var KIND_SHA256)"
KUBECTL_VERSION="$(ci_var KUBECTL_VERSION)"
KUBECTL_SHA256="$(ci_var KUBECTL_SHA256)"

net="sim-ci-$$"
dind="sim-dind-$$"
certs="sim-certs-$$"

cleanup() {
  docker rm -f "$dind" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
  docker volume rm "$certs" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "=== service: $DIND_IMAGE (alias docker, TLS on 2376)"
docker network create "$net" >/dev/null
docker run -d --privileged --name "$dind" --network "$net" --network-alias docker \
  -e DOCKER_TLS_CERTDIR=/certs -v "$certs:/certs" "$DIND_IMAGE" >/dev/null

echo "=== job container: $DOCKER_IMAGE"
docker run --rm --network "$net" \
  -v "$certs:/certs:ro" -v "$root:/builds/project" -w /builds/project \
  -e DOCKER_HOST=tcp://docker:2376 -e DOCKER_TLS_CERTDIR=/certs \
  -e DOCKER_TLS_VERIFY=1 -e DOCKER_CERT_PATH=/certs/client \
  -e KIND_API_HOST=docker \
  -e KIND_VERSION="$KIND_VERSION" -e KIND_SHA256="$KIND_SHA256" \
  -e KUBECTL_VERSION="$KUBECTL_VERSION" -e KUBECTL_SHA256="$KUBECTL_SHA256" \
  "$DOCKER_IMAGE" sh -euc '
    step() { printf "\n\$ %s\n" "$*"; "$@"; }

    # .dind before_script
    for i in $(seq 1 30); do
      docker info >/dev/null 2>&1 && break
      echo "waiting for the docker daemon ($i/30)"; sleep 2
    done
    docker info --format "docker daemon {{.ServerVersion}} ready, storage driver {{.Driver}}"

    # deploy-test script
    step apk add --no-cache --quiet bash curl
    step sh scripts/fetch-verified.sh "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64" "$KIND_SHA256" /usr/local/bin/kind
    step sh scripts/fetch-verified.sh "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" "$KUBECTL_SHA256" /usr/local/bin/kubectl
    step chmod +x /usr/local/bin/kind /usr/local/bin/kubectl

    printf "\n\$ docker build -t orders-api:sim .    (stands in for: docker pull \$IMAGE_REF)\n"
    docker build --quiet --build-arg VERSION=sim -t orders-api:sim . >/dev/null

    rc=0
    {
      step bash scripts/kind-up.sh &&
      step bash scripts/deploy.sh orders-api:sim &&
      step bash scripts/smoke-k8s.sh orders-dev &&
      step bash scripts/netpol-check.sh orders-dev
    } || rc=$?

    # after_script
    if [ "$rc" -ne 0 ]; then
      bash scripts/k8s-diagnostics.sh orders-dev /tmp/diagnostics || true
      cat /tmp/diagnostics/describe-pods.txt /tmp/diagnostics/events.txt 2>/dev/null | tail -n 60
    fi
    step kind delete cluster --name orders-api || true
    printf "\njob exit code: %s\n" "$rc"
    exit "$rc"
  '
