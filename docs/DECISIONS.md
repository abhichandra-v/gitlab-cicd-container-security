# Decision log

One short entry per decision: context, decision, why. Newest last.

## D-001: `doctor` logic lives in `scripts/doctor.sh`

- **Context:** `make doctor` has to check for tools on machines where `make`
  itself may be missing (it is not installed by default on Windows).
- **Decision:** The check is a standalone bash script; the Makefile target only
  calls it.
- **Why:** The check can be run as `bash scripts/doctor.sh` before `make` is
  installed, and it is testable on its own.

## D-002: Makefile recipes run under bash

- **Context:** The repo is developed on Windows (Git Bash) and built on Linux
  runners.
- **Decision:** `SHELL := bash` with `-eu -o pipefail`; no `cmd.exe` or
  PowerShell recipes.
- **Why:** One recipe syntax for both platforms, and failures in pipelines stop
  the target instead of being masked.

## D-003: `kubectl kustomize` is an accepted substitute for standalone `kustomize`

- **Context:** `kubectl` embeds kustomize, so a separate binary is often absent.
- **Decision:** `doctor` reports standalone `kustomize` as missing but does not
  fail on it when `kubectl kustomize` works. Make targets call `$(KUSTOMIZE)`,
  which falls back to `kubectl kustomize`.
- **Why:** Avoids forcing an extra install for an identical renderer. The
  embedded version is printed so version drift is visible.

## D-004: Empty root commit on `main`

- **Context:** Every feature, including the bootstrap, should land as a
  `--no-ff` merge, but a merge needs an existing `main` to merge into.
- **Decision:** `main` starts with one empty commit; `chore/bootstrap` branches
  from it.
- **Why:** Keeps the "one merge per feature" shape from the very first change.

## D-005: `.gitattributes` forces LF line endings

- **Context:** Shell scripts are written on Windows and executed on Linux
  runners and in containers; CRLF breaks the shebang line.
- **Decision:** `* text=auto eol=lf` for the whole repo.
- **Why:** Removes a class of "works locally, fails in CI" errors.

## D-006: Local tooling runs from a pinned toolbox image

- **Context:** The Makefile needs Go, make, kind, Trivy, hadolint, Checkov and
  others. Installing a dozen tools per machine drifts from the versions the
  pipeline uses, and the development machine had only Docker and kubectl.
- **Decision:** `build/toolbox/Dockerfile` copies each tool out of its
  publisher's image, pinned by digest, at the same version as the pipeline.
  `scripts/toolbox.sh make <target>` runs any target inside it with the host
  Docker socket mounted. Running the targets natively still works if the tools
  are installed.
- **Why:** The only local prerequisite is Docker, and "works locally" means
  the same tool versions as CI. The image is never shipped or built by the
  pipeline.

## D-007: Runtime base is `scratch`, not distroless

- **Context:** The brief allows `scratch` or
  `gcr.io/distroless/static-debian12:nonroot`, whichever measures smaller and
  scans clean.
- **Decision:** `scratch`. `build/distroless/Dockerfile` is kept so
  `make size-report` re-measures both on every run.
- **Why:** Measured in `docs/evidence/image-size.txt`: scratch 7.30 MB,
  distroless 10.48 MB (3,180,032 bytes more). The service needs none of what
  distroless adds (CA certificates, tzdata, `/etc/passwd`): it makes no
  outbound TLS calls, logs in UTC and runs as a numeric UID.

## D-008: Image size is measured from `docker save`, not `docker images`

- **Context:** `docker images` reports compressed content on the containerd
  image store (Docker Desktop default) and unpacked layers on overlay2
  (typical CI runner), so the same image shows two different sizes.
- **Decision:** `scripts/size-report.sh` sums the decompressed layer tarballs
  from `docker save`.
- **Why:** One method that gives the same number on any Docker backend, and
  the evidence file states exactly what was measured.

## D-009: The binary has a `healthcheck` subcommand

- **Context:** A `scratch` image has no shell or curl for a Dockerfile
  `HEALTHCHECK`, and Checkov (CKV_DOCKER_2) and Trivy (DS026) flag a missing
  one.
- **Decision:** `orders-api healthcheck` requests its own `/healthz` and exits
  0 or 1. The Dockerfile uses it in exec form.
- **Why:** Satisfies the check for real instead of suppressing it, at the
  cost of about 20 lines of Go and no extra files in the image. Kubernetes
  ignores `HEALTHCHECK` and uses the HTTP probes in the manifests.

## D-010: Pipeline YAML is validated without `glab ci lint`

- **Context:** `glab ci lint` calls the GitLab API and needs a logged-in
  gitlab.com account and an existing project. Neither was available while the
  pipeline was written.
- **Decision:** Validate with `yamllint -s` and Checkov's `gitlab_ci`
  framework, and run each job's script locally in the same pinned image the
  job uses. `glab ci lint` is listed in `docs/SETUP-GITLAB.md` as the first
  thing to run once the project exists.
- **Why:** Catches syntax and script errors early. It does not prove GitLab
  accepts the configuration; only a real pipeline run does.

## D-011: `go-test` runs on the Debian Go image, the build on Alpine

- **Context:** `go test -race` needs cgo and a C compiler, which the Alpine Go
  image does not ship.
- **Decision:** `go-test` uses `golang:1.27.2` (Debian); the Dockerfile build
  stage stays on `golang:1.27.2-alpine3.24`. Same Go version in both.
- **Why:** Race detection is worth more than a smaller CI image, and the
  production binary is built without cgo either way.

## D-012: Trivy suppressions use `.trivyignore.yaml`, not `.trivyignore`

- **Context:** The brief asks for a justification and a review date on every
  suppression. Plain `.trivyignore` is a list of IDs with free-text comments.
- **Decision:** `.trivyignore.yaml`, referenced from `trivy.yaml`.
- **Why:** The YAML form has `statement`, `paths` and `expired_at` fields, so
  a suppression is scoped to one file and stops working on its review date
  instead of living forever.

## D-013: Scan jobs scan to JSON once, then gate on `trivy convert`

- **Context:** The jobs need a readable table in the log, a JSON artifact and
  (for images) a GitLab report. Running the scan three times could give three
  different answers if the vulnerability database updates in between.
- **Decision:** One scan writes JSON; `trivy convert --exit-code 1` prints the
  table from it and is the step that fails the job.
- **Why:** All outputs describe the same scan. Verified locally that
  `convert` exits 1 for vulnerabilities, misconfigurations and secrets.

## D-014: The gate proof was run locally

- **Context:** The brief asks for the failing `trivy-image` job log from a
  GitLab pipeline on `demo/vulnerable-base`. No GitLab project existed yet.
- **Decision:** `docs/evidence/gate-blocks-vulnerable-image.txt` is a local
  run of `scripts/scan-image.sh`, the script the job calls, and says so in
  its header. The branch exists locally, unmerged, ready to push.
- **Why:** It proves the gate logic. It does not prove the GitLab job wiring
  (registry login, `IMAGE_REF` hand-off); that needs the real pipeline.

## D-015: Validators run on rendered overlays, built once

- **Context:** Kustomize bases are templates; what reaches the cluster is the
  rendered overlay. Each validator rendering for itself could use a different
  kustomize version.
- **Decision:** A `render-manifests` job (the pinned kustomize image) writes
  `rendered/dev.yaml` and `rendered/prod.yaml` as artifacts. kubeconform,
  kube-score, trivy-config and checkov all `need` it. `make validate` does the
  same locally.
- **Why:** Every tool judges the bytes that would be applied, and they all
  judge the same bytes.

## D-016: Images are loaded into kind from a single-platform archive

- **Context:** `kind load docker-image` failed for a pulled multi-platform
  image on the Docker containerd image store (`ctr: content digest ... not
  found`). The pipeline deploy test pulls its image the same way.
- **Decision:** `scripts/kind-load.sh` runs `docker save --platform <daemon
  platform>` and `kind load image-archive`, falling back to the plain command
  on Docker versions without `save --platform`.
- **Why:** Works on both image stores. Found by hitting the failure locally.

## D-017: Dev overlay relaxes two checks; prod relaxes none

- **Context:** kind runs a locally loaded image, so `imagePullPolicy: Always`
  cannot work there, and one replica is enough for a throwaway cluster.
  kube-score and Checkov flag both.
- **Decision:** The dev overlay patches the pull policy and adds scoped ignore
  annotations (`kube-score/ignore`, `checkov.io/skip2`). The base and the prod
  overlay stay strict, and prod is scored with `--exit-one-on-warning`.
- **Why:** The exceptions are visible in the overlay that needs them and
  cannot leak into prod.

## D-018: kind-in-dind is kept for `deploy-test`, after a local rehearsal

- **Context:** The brief allows falling back to a render-and-validate job if
  an ephemeral kind cluster inside docker-in-docker proves infeasible on
  shared runners. The known problem is that the kind API server is published
  on the dind host, not on the job container's localhost.
- **Decision:** Keep the real deploy test. `scripts/kind-up.sh` takes
  `KIND_API_HOST=docker`: the API server binds to all interfaces, its
  certificate includes that name, and the kubeconfig points at
  `https://docker:6443`.
- **Why:** `scripts/sim-deploy-test.sh` runs the job's commands against a real
  `docker:dind` service with TLS, using the pipeline's pinned images, and it
  passes (`docs/evidence/deploy-test-dind-rehearsal.txt`). That is not a
  GitLab runner. If the job fails there for resource reasons, the fallback is
  to drop the cluster steps and keep `render-manifests`, `kubeconform` and
  `kube-score`, which already validate the same manifests.

## D-019: `deploy-test` waits for every scan gate

- **Context:** With `needs:`, a job starts as soon as the jobs it lists
  finish, regardless of stage order.
- **Decision:** `deploy-test` lists all seven gating scan jobs in `needs:`,
  not only `build-image`.
- **Why:** Nothing is deployed, even to a throwaway cluster, before the image
  and manifests have passed every gate.

## D-020: Releases retag the tested digest in the registry

- **Context:** A release image could be rebuilt from the tag, or the image
  already built in the tag pipeline could be given the version tag.
- **Decision:** `release-image` runs `docker buildx imagetools create`, which
  adds the tag to the existing manifest in the registry.
- **Why:** The released image is byte-for-byte the one that was scanned and
  deploy-tested. A rebuild could differ (new base layer, new Go patch).

## D-021: `deploy-staging` exits 0 when no cluster is configured

- **Context:** The brief asks for the job to skip cleanly without
  `KUBECONFIG_B64`. A `rules:` condition on the variable would hide the job
  entirely.
- **Decision:** The job always exists as a manual action; the script prints a
  notice and exits 0 when the variable is absent.
- **Why:** The deploy step stays visible in the pipeline graph. The cost is
  that GitLab records a "deployment" to the `staging` environment even though
  nothing was deployed; the job log states that plainly.

## D-022: The pipeline runs on a self-hosted GitLab instance

- **Context:** The plan assumed gitlab.com shared runners. The GitLab that
  was actually available is a private, self-hosted GitLab 18.9 with one
  Docker runner and a container registry.
- **Decision:** Run the pipeline there, in a project inside a group reserved
  for automation, pushing over HTTPS with that group's access token. Evidence
  from it has the instance hostname replaced with `<gitlab-host>`.
- **Why:** A real green pipeline is worth more than a described one. The
  pipeline file has no instance-specific values, so it stays portable to
  gitlab.com. The cost is no public pipeline page or badge.

## D-023: Images are built with Kaniko, not Docker-in-Docker

- **Context:** The brief's default was `docker` + `docker:dind` with TLS. On
  the first GitLab run the dind service failed to start: the runner does not
  allow privileged containers (`mount: permission denied`).
- **Decision:** `build-image` uses Kaniko (the maintained
  `osscontainertools/kaniko` fork; the original Google project is archived),
  pinned by digest. It supersedes the dind build. Local `make image` still
  uses `docker build` on the same Dockerfile.
- **Why:** The runner's policy is a sensible one and not this project's to
  change. A daemonless build removes the need for privilege altogether, which
  is also the better security posture. Verified: green on GitLab, digest
  hand-off to the scan jobs works.

## D-024: `smoke-test` always runs; the kind `deploy-test` is opt-in

- **Context:** The kind-based deploy test needs Docker-in-Docker, so it
  cannot run on the unprivileged runner. The brief's fallback was to reduce it
  to render-and-validate, which `render-manifests`, `kubeconform` and
  `kube-score` already do.
- **Decision:** Add `smoke-test`, which runs the built image as a GitLab
  service container and runs `scripts/smoke.sh` against it; it needs no
  privileges. Keep `deploy-test` unchanged but create it only when
  `PRIVILEGED_RUNNER` is `"true"`. Downstream jobs need `smoke-test` and,
  optionally, `deploy-test`. This narrows D-018 and D-019: the gates now
  guard `smoke-test` everywhere and `deploy-test` where it exists.
- **Why:** Every pipeline still executes the artifact it built, and the full
  Kubernetes test is one variable away on a runner that allows it. The
  Kubernetes deploy itself is evidenced locally and in the dind rehearsal,
  not on GitLab.

## D-025: Releases are retagged with crane

- **Context:** D-020 used `docker buildx imagetools create`, which was run
  from a job with a dind service for `docker login`.
- **Decision:** `release-image` uses `crane tag`, then asserts that the new
  tag resolves to `IMAGE_REF`.
- **Why:** Same registry-side retag, no daemon, and an explicit check that
  the released tag is the tested digest.

## D-026: `v1.0.0` was moved before it was first pushed

- **Context:** `v1.0.0` was created locally on the commit that still built
  with Docker-in-Docker, before any GitLab run. That commit's pipeline cannot
  pass on the runner in use.
- **Decision:** Move the local tag to the commit that includes the Kaniko
  build and the GitLab evidence. `v0.1.0` and `v0.5.0` keep their commits and
  are pushed with `-o ci.skip`.
- **Why:** The tag had never left the machine, so nothing depended on it, and
  a release tag should point at a commit whose pipeline passes.
