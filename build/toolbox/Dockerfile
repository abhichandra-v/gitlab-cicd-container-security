# Local development toolbox: every tool the Makefile needs, at the same pinned
# versions the pipeline uses. Never deployed and never built by the pipeline.
# Usage: scripts/toolbox.sh make <target>
#
# Each tool is copied out of its publisher's own image, pinned by digest.

FROM aquasec/trivy:0.75.0@sha256:af6acf9a6b85dfe389a1941505c0ce9efef52a4719635e1a962f022a3d855daa AS trivy
FROM hadolint/hadolint:v2.15.1-alpine@sha256:a1d49ae1a4e83c1dbad26b8c1ad7588c8bd1e04f4866b34ad3cac50335198552 AS hadolint
FROM golangci/golangci-lint:v2.14.0-alpine@sha256:25925c95ebdc7aee39ecc0e6f4f33ac27b9a91718bc65fdf18a1a5c4c9325ee4 AS golangci
FROM zricethezav/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f AS gitleaks
FROM zegl/kube-score:v1.20.0@sha256:ac4c43ad560af905d66f6bf57b0937c591332e6dbf2167c31193a13b4695ab97 AS kubescore
FROM ghcr.io/yannh/kubeconform:v0.8.0-alpine@sha256:6b90a5f23d846140ce0194fe050b1995e546eba938f3a6bf10c039dd5e24588f AS kubeconform
FROM registry.k8s.io/kubectl:v1.37.1@sha256:b7cab618e281b1ee7484e7b706a96e2135fbb6e072c2a573a7dab4e87d7f2385 AS kubectl
FROM registry.k8s.io/kustomize/kustomize:v5.8.3@sha256:429eda4a1c76a7de458d0c4ca3ded9b5d764899ff6bdaeccc1d98b1b6ee873e4 AS kustomize
FROM docker:29.9.0-cli@sha256:1a4c7cb63513f349bdad01fcc6e0f3f2f67d37b9da86f14dc0d4a0942eecda00 AS dockercli

FROM golang:1.27.2-trixie@sha256:47667934874913a449b96faa7ef4777fa285d9ec29126ee80ed61c45b7cccf0e

ARG KIND_VERSION=v0.33.0
ARG GOTESTSUM_VERSION=v1.13.0
ARG CHECKOV_VERSION=3.3.28
ARG YAMLLINT_VERSION=1.38.0

# apt packages are not version-pinned: the base image digest fixes the Debian
# snapshot they resolve against, and this image is never shipped.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends jq python3-venv \
 && rm -rf /var/lib/apt/lists/*

RUN GOBIN=/usr/local/bin go install "sigs.k8s.io/kind@${KIND_VERSION}" \
 && GOBIN=/usr/local/bin go install "gotest.tools/gotestsum@${GOTESTSUM_VERSION}" \
 && go clean -cache -modcache

RUN python3 -m venv /opt/pytools \
 && /opt/pytools/bin/pip install --no-cache-dir "checkov==${CHECKOV_VERSION}" "yamllint==${YAMLLINT_VERSION}" \
 && ln -s /opt/pytools/bin/checkov /opt/pytools/bin/yamllint /usr/local/bin/

COPY --from=trivy       /usr/local/bin/trivy     /usr/local/bin/trivy
COPY --from=trivy       /contrib                 /contrib
COPY --from=hadolint    /bin/hadolint            /usr/local/bin/hadolint
COPY --from=golangci    /usr/bin/golangci-lint   /usr/local/bin/golangci-lint
COPY --from=gitleaks    /usr/bin/gitleaks        /usr/local/bin/gitleaks
COPY --from=kubescore   /usr/bin/kube-score      /usr/local/bin/kube-score
COPY --from=kubeconform /kubeconform             /usr/local/bin/kubeconform
COPY --from=kubectl     /bin/kubectl             /usr/local/bin/kubectl
COPY --from=kustomize   /app/kustomize           /usr/local/bin/kustomize
COPY --from=dockercli   /usr/local/bin/docker    /usr/local/bin/docker
COPY --from=dockercli   /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx

# The repo is bind-mounted from the host and owned by a different user.
RUN git config --system --add safe.directory /src

WORKDIR /src
