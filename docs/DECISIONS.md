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
