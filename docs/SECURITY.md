# Security

What each control in this repo does, the evidence that it works, and what it
does not cover.

## Container image

The production image is built by the root [`Dockerfile`](../Dockerfile).

| Choice | What it buys | Evidence |
|---|---|---|
| Multi-stage build; the Go toolchain stays in the build stage | Compiler, package manager and source never reach the runtime image | [`image-history.txt`](evidence/image-history.txt): one content layer |
| `CGO_ENABLED=0` static binary | No libc dependency, so the binary runs on an empty base | [`image-contents.txt`](evidence/image-contents.txt) |
| `FROM scratch` runtime | No shell, no package manager, no OS packages to patch or exploit | [`image-contents.txt`](evidence/image-contents.txt): `/bin/sh`, `/bin/bash`, `/busybox` all fail to start |
| `-trimpath -ldflags "-s -w"` | No build-machine paths, no symbol or debug tables; smaller binary | [`image-size.txt`](evidence/image-size.txt) |
| `USER 65532:65532` (numeric) | Runs unprivileged; Kubernetes can enforce `runAsNonRoot` without `/etc/passwd` | [`image-inspect.txt`](evidence/image-inspect.txt), [`image-run-hardened.txt`](evidence/image-run-hardened.txt) |
| Nothing written to disk at runtime | Works with a read-only root filesystem and all capabilities dropped | [`image-run-hardened.txt`](evidence/image-run-hardened.txt): `--read-only --cap-drop ALL` |
| Base images pinned by tag **and** digest | A re-pushed tag cannot change what is built | `FROM` lines; [`image-size.txt`](evidence/image-size.txt) |
| Allowlist `.dockerignore` | Git history, docs and local env files never enter the build context | [`.dockerignore`](../.dockerignore) |
| `HEALTHCHECK` calls `orders-api healthcheck` | Health probing without adding curl or a shell to the image | [`image-run-hardened.txt`](evidence/image-run-hardened.txt) |

### Measured result

From [`image-size.txt`](evidence/image-size.txt), uncompressed local sizes:

| Image | Dockerfile | Size |
|---|---|---|
| Naive (full `golang` image, single stage) | `build/naive/Dockerfile` | 1020.32 MB |
| Distroless static | `build/distroless/Dockerfile` | 10.48 MB |
| **Hardened (scratch)** | `Dockerfile` | **7.30 MB** |

That is a 139.7 : 1 ratio, a 99.28% reduction. The hardened image is the
7,299,232-byte binary and nothing else.

### What the image hardening does not do

- **It does not make the Go code safe.** A bug in a handler is still a bug.
  The image limits what an attacker can do after exploiting one (no shell,
  no writable filesystem, no capabilities), not whether they can.
- **It does not remove Go standard-library vulnerabilities.** The binary
  embeds the standard library; a CVE there needs a rebuild on a patched Go
  version. The image scan covers this (it reads the Go build info out of the
  binary), which is why the Go version is pinned and bumped deliberately.
- **`scratch` has no CA certificates or timezone data.** This service makes
  no outbound TLS calls and logs in UTC, so it needs neither. A service that
  calls HTTPS endpoints would have to copy `ca-certificates.crt` in, or use
  distroless.
- **`--read-only`, `--cap-drop ALL` and the seccomp profile are runtime
  settings**, not image properties. The image is built to tolerate them; the
  Kubernetes manifests are what enforce them.
- **No debugging tools in the container.** Use `kubectl debug` with an
  ephemeral container; see the runbook.

### The comparison images

`build/naive/Dockerfile` and `build/distroless/Dockerfile` exist only so
`make size-report` can measure them. The naive one is deliberately bad (runs
as root, ships the toolchain). Neither is built, pushed or deployed by the
pipeline, and the scanners are configured to skip `build/naive`.

## Scan gates

Every job in the `scan` stage exits non-zero on a finding, and a failed job
fails the pipeline. Nothing in this stage is `allow_failure`. `make scan` runs
the same commands locally with the same configuration files.

| Job | Tool | Fails on | Catches | Does not catch |
|---|---|---|---|---|
| `trivy-fs` | Trivy `fs` (`vuln,secret,misconfig`) | Any finding | Vulnerable Go module versions in `go.mod`; secrets in the working tree; Dockerfile misconfigurations | Vulnerabilities that only exist in the built image (base OS packages); secrets already deleted from the tree |
| `trivy-config` | Trivy `config` | Any finding | Misconfigured Dockerfiles and Kubernetes manifests (root user, missing limits, privileged pods) | Whether the running cluster matches the manifests |
| `trivy-image` | Trivy `image` | HIGH or CRITICAL with a fix available | OS-package and Go standard-library CVEs in the exact image digest that was pushed | CVEs with no fix yet (`--ignore-unfixed`); MEDIUM and LOW; flaws in this repo's own code |
| `checkov` | Checkov (`dockerfile`, `kubernetes`, `gitlab_ci`) | Any failed check | Policy violations in Dockerfiles, manifests and the pipeline definition itself | Runtime behaviour; anything outside those three frameworks |
| `gitleaks` | gitleaks `git`, full history | Any leak | Secrets in any commit, including ones removed later | Secrets that match no rule (custom token formats); secrets outside git |
| `hadolint` (lint stage) | hadolint | Any warning | Dockerfile bad practice: unpinned bases, shell pitfalls | Security of the base image contents |
| `sbom` | Trivy `image --format cyclonedx` | Never (it records, it does not gate) | Gives a component inventory for later CVE lookups | It is not a scan |

Why `trivy-image` uses a narrower rule than the other gates: an unfixed CVE
cannot be resolved by a code change, so failing on it would only teach people
to ignore a red pipeline. A fixable HIGH or CRITICAL always has an action
(bump the base image or the Go version), so it always blocks.

### Proof that the gate blocks

[`evidence/gate-blocks-vulnerable-image.txt`](evidence/gate-blocks-vulnerable-image.txt)
is the output of the gate script against two images:

- The `demo/vulnerable-base` branch, which swaps the runtime base for
  end-of-life `alpine:3.12.0`: **36 findings (32 HIGH, 4 CRITICAL), exit
  code 1**.
- The hardened image: no findings, exit code 0.

That run was local, using the script the pipeline job calls. The GitLab job
log for the same branch is still to be captured
([SETUP-GITLAB.md](SETUP-GITLAB.md), step 7).

## Suppressions

A suppression is allowed only with **a one-line justification and a review
date**. Current list:

| Where | What is suppressed | Justification | Review by |
|---|---|---|---|
| `.trivyignore.yaml` | DS-0002 (non-root `USER`) for `build/toolbox/Dockerfile` | Local dev toolbox, never shipped; root is needed for the host Docker socket | 2027-04-13 |
| `.trivyignore.yaml` | DS-0026 (`HEALTHCHECK`) for `build/toolbox/Dockerfile` | One-shot commands, nothing long-running to check | 2027-04-13 |
| `build/toolbox/Dockerfile` (inline) | CKV_DOCKER_3, CKV_DOCKER_2 | Same two findings, Checkov's IDs | 2027-04-13 |
| `trivy.yaml`, `.checkov.yaml` (`skip-dirs` / `skip-path`) | The whole `build/naive/` directory | Deliberately bad comparison image; its findings are the point, and it is never built by the pipeline | 2027-04-13 |

How the dates are enforced:

- Trivy: each `.trivyignore.yaml` entry has `expired_at`. After that date
  Trivy stops honouring the entry and the pipeline goes red until someone
  reviews it.
- Checkov has no expiry mechanism. The date is in the skip comment, and the
  runbook's version-update checklist includes re-reading them.

Adding one: put the finding ID, the narrowest path that works, the reason and
a date no more than six months out. Never suppress by severity or by whole
scanner.
