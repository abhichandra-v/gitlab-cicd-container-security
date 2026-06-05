SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

IMAGE   ?= orders-api:local
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)

# Standalone kustomize if present, otherwise the copy embedded in kubectl.
KUSTOMIZE ?= $(shell command -v kustomize >/dev/null 2>&1 && echo kustomize || echo kubectl kustomize)

.PHONY: help
help: ## List targets
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-14s %s\n", $$1, $$2}'

.PHONY: doctor
doctor: ## Check the local toolchain and list what is missing
	@bash scripts/doctor.sh

.PHONY: toolbox
toolbox: ## Build the toolbox image, then run any target with: scripts/toolbox.sh make <target>
	TOOLBOX_REBUILD=1 bash scripts/toolbox.sh true

.PHONY: fmt-check
fmt-check: ## Fail if any Go file is not gofmt-formatted
	@unformatted="$$(gofmt -l .)"; \
	if [ -n "$$unformatted" ]; then echo "not gofmt-formatted:"; echo "$$unformatted"; exit 1; fi

.PHONY: lint
lint: ## golangci-lint, hadolint and yamllint (same configs as the pipeline)
	golangci-lint run --timeout 5m ./...
	hadolint Dockerfile build/naive/Dockerfile build/distroless/Dockerfile build/toolbox/Dockerfile
	yamllint -s .

.PHONY: test
test: fmt-check ## go vet, then unit tests with the race detector and coverage
	go vet ./...
	go test -race -count=1 -coverprofile=coverage.out ./...
	@go tool cover -func=coverage.out | tail -n 1

.PHONY: build
build: ## Build the static binary into bin/
	CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o bin/orders-api ./cmd/orders-api

.PHONY: api-evidence
api-evidence: ## Run the binary, curl every endpoint, write docs/evidence/api-smoke.txt
	bash scripts/api-evidence.sh

.PHONY: image
image: ## Build the hardened image as $(IMAGE)
	docker build --build-arg VERSION=$(VERSION) -t $(IMAGE) .

.PHONY: size-report
size-report: ## Build hardened, distroless and naive images; write docs/evidence/image-size.txt
	bash scripts/size-report.sh

.PHONY: image-evidence
image-evidence: image ## Record image history, config and contents; run it locked down
	bash scripts/image-evidence.sh $(IMAGE)

.PHONY: scan
scan: image ## Run every scan gate the pipeline runs; any finding fails
	trivy fs --scanners vuln,secret,misconfig --exit-code 1 --no-progress .
	trivy config --exit-code 1 .
	sh scripts/scan-image.sh $(IMAGE) reports
	checkov --config-file .checkov.yaml
	gitleaks git --redact --no-banner --exit-code 1 .

.PHONY: sbom
sbom: image ## Write a CycloneDX SBOM of the image to reports/sbom.cdx.json
	mkdir -p reports
	trivy image --no-progress --format cyclonedx --output reports/sbom.cdx.json $(IMAGE)

.PHONY: clean
clean: ## Remove build output
	rm -rf bin coverage.out junit.xml reports

# Targets added in later phases (see docs/PLAN.md):
# validate, kind-up, deploy, smoke
