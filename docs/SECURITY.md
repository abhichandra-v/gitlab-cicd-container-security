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
