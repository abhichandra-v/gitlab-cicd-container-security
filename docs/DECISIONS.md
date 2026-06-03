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
