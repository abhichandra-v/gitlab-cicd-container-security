#!/usr/bin/env bash
# Checks that the local toolchain is present. Installs nothing.
# Exit 0 when every required tool is found, 1 otherwise.
set -u

required=(go docker kind kubectl kustomize trivy hadolint)
missing=()

version_of() {
  case "$1" in
    go)        go version 2>/dev/null ;;
    docker)    docker --version 2>/dev/null ;;
    kind)      kind version 2>/dev/null ;;
    kubectl)   kubectl version --client 2>/dev/null | head -n 1 ;;
    kustomize) kustomize version 2>/dev/null ;;
    trivy)     trivy --version 2>/dev/null | head -n 1 ;;
    hadolint)  hadolint --version 2>/dev/null ;;
  esac
}

for tool in "${required[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf 'ok       %-10s %s\n' "$tool" "$(version_of "$tool")"
  elif [ "$tool" = kustomize ] && kubectl kustomize --help >/dev/null 2>&1; then
    embedded=$(kubectl version --client 2>/dev/null | grep -i kustomize)
    printf 'ok       %-10s standalone binary missing, using kubectl kustomize (%s)\n' "$tool" "$embedded"
  else
    printf 'MISSING  %-10s\n' "$tool"
    missing+=("$tool")
  fi
done

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    printf 'ok       %-10s %s\n' "dockerd" "engine reachable"
  else
    printf 'DOWN     %-10s %s\n' "dockerd" "docker CLI found but the engine is not reachable"
    missing+=("dockerd (start Docker)")
  fi
fi

if [ "${#missing[@]}" -gt 0 ]; then
  printf '\nMissing or unavailable:\n'
  printf '  - %s\n' "${missing[@]}"
  printf '\nNothing was installed. Install the tools above and re-run.\n'
  exit 1
fi

printf '\nAll required tools found.\n'
