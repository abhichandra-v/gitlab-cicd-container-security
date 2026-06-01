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

# Targets below are added in later phases (see docs/PLAN.md):
# test, image, size-report, scan, validate, kind-up, deploy, smoke, clean
