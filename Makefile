SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

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

.PHONY: clean
clean: ## Remove build output
	rm -rf bin coverage.out junit.xml reports

# Targets added in later phases (see docs/PLAN.md):
# image, size-report, scan, validate, kind-up, deploy, smoke
