# Build plan

Checklist copied from the build brief. Items are ticked in the same commit as
the work that completes them. 🛑 marks a checkpoint that needs the repo owner's
GitLab account.

## Phase 0: `chore/bootstrap`

- [x] `.gitignore`, `.editorconfig`, MIT `LICENSE`
- [x] README skeleton (title, purpose, status)
- [x] `docs/PLAN.md`, `docs/DECISIONS.md`
- [x] Makefile skeleton with a `doctor` target (go, docker, kind, kubectl, kustomize, trivy, hadolint)

## Phase 1: `feat/orders-api`

- [x] Order model and in-memory store behind a mutex
- [x] Handlers: `POST /orders`, `GET /orders`, `GET /orders/{id}`
- [x] `GET /healthz`, `GET /readyz`
- [x] Config from env vars, `log/slog` JSON logs, graceful shutdown on SIGTERM
- [x] Table-driven tests, 80%+ coverage on handlers and store, `go vet` clean
- [x] `make test` green
- [x] Every endpoint exercised with curl, transcript in `docs/evidence/api-smoke.txt`

## Phase 2: `feat/container-image` → tag `v0.1.0`

- [x] `Dockerfile` (multi-stage, hardened, numeric non-root UID)
- [x] `build/naive/Dockerfile` (comparison only)
- [x] `.dockerignore`, `make image`
- [x] `scripts/size-report.sh` writes `docs/evidence/image-size.txt` (bytes, MB, ratio, base digests)
- [x] Final image ≤ 8 MB, or the real number reported (measured: 7.30 MB)
- [x] Runs with `--read-only --cap-drop ALL --user 65532:65532`
- [x] `docker history` and `docker inspect` output saved to evidence
- [x] Image hardening choices documented
- [x] Tag `v0.1.0`

## Phase 3: `ci/gitlab-pipeline-core`

- [ ] `.gitlab-ci.yml` skeleton: `workflow:rules`, `rules:`, `needs:`, cached Go modules
- [ ] `go-lint` (golangci-lint), `hadolint`
- [ ] `go-test` (coverage regex, JUnit via gotestsum, coverage artifact)
- [ ] `build-image` (dind + TLS, tags short SHA and branch slug, pushes, digest artifact)
- [ ] YAML validated locally
- [ ] `docs/SETUP-GITLAB.md`

🛑 **Checkpoint A:** owner creates the GitLab project, pushes, confirms the pipeline is green.

## Phase 4: `feat/security-scanning`

- [ ] `trivy-fs` (`vuln,secret,misconfig`)
- [ ] `trivy-config` (Dockerfile and k8s manifests)
- [ ] `trivy-image` gate (`HIGH,CRITICAL`, `--ignore-unfixed`, `--exit-code 1`; table, JSON, GitLab report)
- [ ] `checkov` (`dockerfile`, `kubernetes`, `gitlab_ci`)
- [ ] `gitleaks` on git history
- [ ] SBOM artifact (CycloneDX)
- [ ] Suppression policy: justification and review date on every skip
- [ ] Gate proven on `demo/vulnerable-base`, log in `docs/evidence/gate-blocks-vulnerable-image.txt` (branch not merged)
- [ ] Scan gates and suppression policy documented
- [ ] TODO: `kube-score` and `kubeconform` jobs are added in Phase 5, once manifests exist

## Phase 5: `feat/k8s-manifests` → tag `v0.5.0`

- [ ] `k8s/base`: Deployment, Service, ServiceAccount, PodDisruptionBudget
- [ ] Pod hardening: non-root, read-only root fs, no privilege escalation, drop ALL, seccomp `RuntimeDefault`, requests/limits, three probes
- [ ] Default-deny NetworkPolicy plus allow rule
- [ ] `k8s/overlays/dev`, `k8s/overlays/prod` (replicas, image tag via `images:`)
- [ ] `kube-score` and `kubeconform` (strict) jobs, `make validate`
- [ ] Both overlays pass kubeconform strict, kube-score and Checkov (documented skips only)
- [ ] `make kind-up deploy smoke` works locally
- [ ] Tag `v0.5.0`

## Phase 6: `ci/deploy-automation`

- [ ] `deploy-test`: ephemeral kind cluster in the job, dev overlay, rollout wait, `scripts/smoke.sh`, diagnostics on failure, always tears down
- [ ] `deploy-staging`: manual, `environment:`, `KUBECONFIG_B64`, skips cleanly when absent
- [ ] `release`: on `v*` tags, retag image, GitLab release
- [ ] Deploy and rollback flow documented

🛑 **Checkpoint B:** owner runs the full pipeline (including a tag), sends results, adds screenshots under `docs/evidence/screenshots/`.

## Phase 7: `docs/final-polish` → tag `v1.0.0`

- [ ] `README.md`: purpose, Mermaid diagrams, size table from evidence, security-gate table, quick start, GitHub/GitLab pairing, badge, evidence links
- [ ] `docs/PIPELINE.md`
- [ ] `docs/SECURITY.md`
- [ ] `docs/RUNBOOK.md`
- [ ] Every README claim maps to a file in `docs/evidence/`
- [ ] `make doctor test image scan` clean, `git status` clean, gitleaks clean on full history
- [ ] Tag `v1.0.0`

## Stretch (only after `v1.0.0`, only on request)

- [ ] cosign keyless signing with a GitLab ID token
- [ ] SBOM attestation
- [ ] Renovate config for pinned versions

## Definition of done

- [ ] Pipeline green on GitLab: lint → test → build → scan → deploy-test (→ manual deploy, tag release)
- [ ] Final image measured and recorded next to the naive image in `docs/evidence/image-size.txt`
- [ ] A scan gate demonstrably blocks a vulnerable image (evidence file)
- [ ] Manifests pass kubeconform strict, kube-score and Checkov
- [ ] README, PIPELINE, SECURITY, RUNBOOK written from real outputs
- [ ] History is feature-branch merges with Conventional Commits and no secrets
- [ ] Tags `v0.1.0`, `v0.5.0`, `v1.0.0` exist locally
