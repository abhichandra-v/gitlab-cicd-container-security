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

- [x] `.gitlab-ci.yml` skeleton: `workflow:rules`, `rules:`, `needs:`, cached Go modules
- [x] `go-lint` (golangci-lint), `hadolint`
- [x] `go-test` (coverage regex, JUnit via gotestsum, coverage artifact)
- [x] `build-image` (dind + TLS, tags short SHA and branch slug, pushes, digest artifact)
- [x] YAML validated locally (yamllint strict, Checkov `gitlab_ci`; `glab ci lint` needs a gitlab.com login)
- [x] `docs/SETUP-GITLAB.md`

🛑 **Checkpoint A:** owner creates the GitLab project, pushes, confirms the pipeline is green.

- [x] Pipeline confirmed green on GitLab (after the Kaniko change; see "GitLab run" below)

## Phase 4: `feat/security-scanning`

- [x] `trivy-fs` (`vuln,secret,misconfig`)
- [x] `trivy-config` (Dockerfile and k8s manifests)
- [x] `trivy-image` gate (`HIGH,CRITICAL`, `--ignore-unfixed`, `--exit-code 1`; table, JSON, GitLab report)
- [x] `checkov` (`dockerfile`, `kubernetes`, `gitlab_ci`)
- [x] `gitleaks` on git history
- [x] SBOM artifact (CycloneDX)
- [x] Suppression policy: justification and review date on every skip
- [x] Gate proven on `demo/vulnerable-base`, log in `docs/evidence/gate-blocks-vulnerable-image.txt` (branch not merged). Local run of the job's script; the GitLab job log is still to be captured
- [x] Scan gates and suppression policy documented
- [x] `kube-score` and `kubeconform` jobs (added in Phase 5, once manifests existed)

## Phase 5: `feat/k8s-manifests` → tag `v0.5.0`

- [x] `k8s/base`: Deployment, Service, ServiceAccount, PodDisruptionBudget
- [x] Pod hardening: non-root, read-only root fs, no privilege escalation, drop ALL, seccomp `RuntimeDefault`, requests/limits, three probes
- [x] Default-deny NetworkPolicy plus allow rule
- [x] `k8s/overlays/dev`, `k8s/overlays/prod` (replicas, image tag via `images:`)
- [x] `kube-score` and `kubeconform` (strict) jobs, `make validate`
- [x] Both overlays pass kubeconform strict, kube-score and Checkov (documented skips only)
- [x] `make kind-up deploy smoke` works locally
- [x] Tag `v0.5.0`

## Phase 6: `ci/deploy-automation`

- [x] `deploy-test`: ephemeral kind cluster in the job, dev overlay, rollout wait, `scripts/smoke.sh`, diagnostics on failure, always tears down
- [x] `deploy-staging`: manual, `environment:`, `KUBECONFIG_B64`, skips cleanly when absent
- [x] `release`: on `v*` tags, retag image, GitLab release
- [x] Deploy and rollback flow documented

🛑 **Checkpoint B:** owner runs the full pipeline (including a tag), sends results, adds screenshots under `docs/evidence/screenshots/`.

- [x] Full pipeline run on GitLab, including a tag (see "GitLab run" below)
- [ ] Screenshots added under `docs/evidence/screenshots/`
- [ ] `deploy-staging` success path exercised against a real cluster

## Phase 7: `docs/final-polish` → tag `v1.0.0`

- [x] `README.md`: purpose, Mermaid diagrams, size table from evidence, security-gate table, quick start, GitHub/GitLab pairing, badge, evidence links
- [x] `docs/PIPELINE.md`
- [x] `docs/SECURITY.md`
- [x] `docs/RUNBOOK.md`
- [x] Every README claim maps to a file in `docs/evidence/`
- [x] `make doctor test image scan` clean, `git status` clean, gitleaks clean on full history
- [x] Tag `v1.0.0`

## Stretch (only after `v1.0.0`, only on request)

- [ ] cosign keyless signing with a GitLab ID token
- [ ] SBOM attestation
- [ ] Renovate config for pinned versions

## Definition of done

- [x] Pipeline green on GitLab: lint → test → build → scan → smoke-test (→ manual deploy, tag release). Self-hosted instance, unprivileged runner; see `docs/evidence/gitlab/`
- [x] Final image measured and recorded next to the naive image in `docs/evidence/image-size.txt` (7.30 MB vs 1020.32 MB)
- [x] A scan gate demonstrably blocks a vulnerable image (local run and GitLab job log)
- [x] Manifests pass kubeconform strict, kube-score and Checkov
- [x] README, PIPELINE, SECURITY, RUNBOOK written from real outputs
- [x] History is feature-branch merges with Conventional Commits and no secrets
- [x] Tags `v0.1.0`, `v0.5.0`, `v1.0.0` exist locally

## GitLab run

- [x] `glab ci lint` against the real project: valid
- [x] First pipeline on `main`: failed at `build-image` (runner is not privileged, dind cannot start)
- [x] Build moved to Kaniko, `smoke-test` added, kind `deploy-test` made opt-in (D-023, D-024)
- [x] Green pipeline on `main`
- [x] `demo/vulnerable-base` pushed: only `trivy-image` fails; job log saved
- [x] `deploy-staging` played without a kubeconfig: skips cleanly

## Still open

- [ ] Kind-based `deploy-test` on a GitLab runner (needs a privileged runner)
- [ ] `deploy-staging` against a real cluster with `KUBECONFIG_B64`
- [ ] Three screenshots under `docs/evidence/screenshots/`; README placeholders replaced
- [ ] Push to GitHub (`origin`)
