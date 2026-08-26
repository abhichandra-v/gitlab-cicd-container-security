# Runbook

Procedures for the things that go wrong or need doing regularly. Commands
assume the repo root. `scripts/toolbox.sh <command>` runs anything below in
the pinned toolbox image if the tool is not installed locally.

- [Deploying](#deploying)
- [Rolling back a bad deploy](#rolling-back-a-bad-deploy)
- [Triaging a failed scan](#triaging-a-failed-scan)
- [Debugging a failed deploy-test](#debugging-a-failed-deploy-test)
- [Rotating CI variables](#rotating-ci-variables)
- [Updating pinned versions](#updating-pinned-versions)
- [Cutting a release](#cutting-a-release)

## Deploying

There are three ways the image reaches a cluster.

| Path | Trigger | Target | What is deployed |
|---|---|---|---|
| `make kind-up deploy smoke` | By hand | Local kind cluster, namespace `orders-dev` | The locally built `orders-api:local` |
| `smoke-test` job | Every pipeline, after all scan gates | A service container next to the job (no cluster) | The image `build-image` pushed in the same pipeline |
| `deploy-test` job | Pipelines on privileged runners (`PRIVILEGED_RUNNER=true`), after all scan gates | Throwaway kind cluster inside the job | The digest `build-image` pushed in the same pipeline |
| `deploy-staging` job | Manual button on `main` and on `vX.Y.Z` tags | The cluster in `KUBECONFIG_B64`, namespace `orders-staging` | The same digest, applied through the prod overlay |

`deploy-staging` runs `scripts/deploy-staging.sh`, which:

1. Exits 0 with a notice if `KUBECONFIG_B64` is absent (no cluster
   configured, or the ref is not protected).
2. Refuses an `IMAGE_REF` that is not a digest reference.
3. Generates a throwaway overlay on top of `k8s/overlays/prod` that sets the
   namespace and pins the image to that digest.
4. Applies it and waits for `kubectl rollout status`.
5. On a failed rollout: prints pods, the deployment description and logs,
   runs `kubectl rollout undo`, and exits non-zero.

To see exactly what it would apply, without a cluster:

```bash
DRY_RUN=1 IMAGE_REF=registry.gitlab.com/abhichandra-v/gitlab-cicd-container-security@sha256:<digest> bash scripts/deploy-staging.sh
```

[`evidence/deploy-staging-paths.txt`](evidence/deploy-staging-paths.txt) shows
the skip, the rejected tag, the dry run and a failed rollout. The success
path against a real staging cluster has not been exercised: there is no
staging cluster yet.

## Rolling back a bad deploy

The Deployment keeps five old ReplicaSets (`revisionHistoryLimit: 5`), so the
previous version can be restored without a pipeline run.

```bash
kubectl -n orders-staging rollout undo deployment/orders-api
```

```bash
kubectl -n orders-staging rollout status deployment/orders-api --timeout 180s
```

To go back further than one revision:

```bash
kubectl -n orders-staging rollout history deployment/orders-api
```

```bash
kubectl -n orders-staging rollout undo deployment/orders-api --to-revision <n>
```

What to expect, from a real run on kind
([`evidence/rollback.txt`](evidence/rollback.txt)):

- A rollout to an image that cannot start never becomes ready. Because the
  strategy is `maxUnavailable: 0`, the old pods keep serving while it hangs;
  the smoke test passes throughout.
- `rollout undo` removes the broken pod and the Deployment reports rolled out
  within seconds.
- kubectl warns that the `last-applied-configuration` annotation is now stale.
  That is expected after an imperative rollback. The next pipeline deploy
  overwrites it.

After rolling back:

1. Find out why the new version failed before redeploying:
   `kubectl -n orders-staging describe pod <pod>` and
   `kubectl -n orders-staging logs <pod> --previous`.
2. Revert or fix the commit on `main`. A rollback changes the cluster, not the
   repository: the next `deploy-staging` run would deploy the bad digest again.

The rollback restores the pod template (image, env, probes, security
context). It does not restore other objects the bad release changed, such as
the NetworkPolicy or Service. For those, re-apply the previous commit:

```bash
git checkout <good-sha> -- k8s && kubectl apply -k k8s/overlays/prod
```

The image has no shell. To look inside a running pod, attach a debug
container that shares its process namespace:

```bash
kubectl -n orders-staging debug -it <pod> --image=busybox:1.37 --target=orders-api --profile=restricted
```

## Triaging a failed scan

A red job in the `scan` stage means a finding, not a flake. Open the job log
first; every scan job prints a table and uploads a JSON artifact.

| Job | First question | Usual fix |
|---|---|---|
| `trivy-image` | Which package, and is it the base image or the Go standard library? | `stdlib` or `gobinary`: bump the Go version. OS package: bump the base image. Then rebuild. |
| `trivy-fs` | Vulnerability, secret or misconfiguration? | Vulnerable module: `go get -u <module>` and `go mod tidy`. Secret: see "A leaked secret" below. |
| `trivy-config` | Which file and check ID (`DS-…`, `KSV-…`)? | Fix the Dockerfile or manifest. The log links to the check description. |
| `checkov` | Which `CKV_…` ID and resource? | Fix the resource. The log prints a guide URL. |
| `gitleaks` | Which commit and rule? | See "A leaked secret" below. |
| `kubeconform` | Which field failed schema validation? | Typo or a field from a different API version. Check against `kubectl explain`. |
| `kube-score` | Which check, on which overlay? | Fix the base manifest. Dev-only exceptions are annotations in `k8s/overlays/dev`. |

Reproduce locally with the same tool versions and configuration:

```bash
scripts/toolbox.sh make scan
```

```bash
scripts/toolbox.sh make validate
```

### A fixable CVE in the image

1. Read the "Fixed Version" column in the `trivy-image` table.
2. For the Go standard library, update the Go version in `Dockerfile`,
   `build/naive/Dockerfile`, `build/distroless/Dockerfile`,
   `build/toolbox/Dockerfile` and `GO_IMAGE` in `.gitlab-ci.yml` (see
   "Updating pinned versions").
3. Rebuild and rescan: `scripts/toolbox.sh make scan`.

Do not suppress a fixable HIGH or CRITICAL to get a green pipeline.

### A CVE that cannot be fixed yet

`trivy-image` already ignores CVEs with no fix (`--ignore-unfixed`), so this
only comes up for a fixable CVE whose fix cannot be taken right now. If the
vulnerable code is not reachable, add an entry under `vulnerabilities:` in
`.trivyignore.yaml` with a `statement` and an `expired_at` at most six months
out, and add a row to the table in [SECURITY.md](SECURITY.md#suppressions).

### A false positive in a config scanner

Same policy: the narrowest suppression that works (one ID, one path), a
justification, a review date. Trivy: `.trivyignore.yaml`. Checkov: an inline
`#checkov:skip=<ID>:<reason>` comment, or a `checkov.io/skip<n>` annotation on
a Kubernetes object.

### A leaked secret

1. **Revoke the secret first.** Removing it from git does not un-leak it; it
   has been in a public repository.
2. Remove it from the working tree and commit.
3. `gitleaks` scans full history, so the job stays red while the secret is in
   any commit. Either rewrite history (`git filter-repo`) and force-push both
   remotes, or, if the secret is revoked and history is to be kept, add the
   finding's fingerprint to a `.gitleaksignore` file with a comment saying it
   is revoked.

### An expired suppression

A `.trivyignore.yaml` entry past its `expired_at` stops working, and the
finding fails the job again. That is the review reminder. Either fix the
underlying issue or renew the date with a fresh justification.

## Debugging a failed deploy-test

`deploy-test` only exists when `PRIVILEGED_RUNNER` is `"true"`. Set that
variable only if the runner allows privileged containers; on a runner that
does not, the dind service fails with `mount: permission denied` and the job
waits for a daemon that never starts. `smoke-test` covers the unprivileged
case.

The job uploads a `diagnostics/` artifact on failure (pod descriptions,
events, logs).

| Symptom in the log | Likely cause |
|---|---|
| `waiting for the docker daemon (30/30)` then failure | The `docker:dind` service did not start because the runner is not privileged. Unset `PRIVILEGED_RUNNER`. |
| `kind create cluster` hangs or fails | Resource limits on the runner. Retry once; if it persists, see D-018 in DECISIONS.md. |
| `Unable to connect to the server` / certificate error for `docker` | `KIND_API_HOST` is not set to the dind service alias. |
| `ErrImagePull` / `ImagePullBackOff` in `describe-pods.txt` | The image was not loaded into kind: check the `kind-load.sh` step. |
| `violates PodSecurity "restricted"` in `events.txt` | A manifest change weakened the pod's security context. |
| Rollout times out, pod `Running` but not `Ready` | A probe is failing: check `logs.txt` and the probe paths. |
| Smoke test fails on one request | A real regression. `logs.txt` has the request log. |

Run the same job on a workstation, against a real `docker:dind` service:

```bash
bash scripts/sim-deploy-test.sh
```

## Rotating CI variables

The pipeline needs no secret of its own: registry access uses the job token.
The only stored secret is `KUBECONFIG_B64`.

1. Create a new credential in the cluster. Use a ServiceAccount limited to the
   `orders-staging` namespace, not a personal or cluster-admin kubeconfig.
2. Build a kubeconfig for it and encode it:

   ```bash
   base64 -w0 < staging-kubeconfig.yaml
   ```

3. GitLab → **Settings → CI/CD → Variables** → edit `KUBECONFIG_B64`. Keep
   **Masked** and **Protected** ticked and "Expand variable reference"
   unticked.
4. Run `deploy-staging` once to confirm it works.
5. Revoke the old credential in the cluster (delete the old token Secret or
   ServiceAccount). Rotation is not finished until the old one stops working.
6. Delete the local `staging-kubeconfig.yaml`.

Rotate on a schedule (every 90 days is reasonable), when someone with access
leaves, and immediately if the value may have been exposed.

Because the variable is protected, it is only available on protected branches
and tags (`main`, `v*`). On any other ref `deploy-staging` skips, by design.

## Updating pinned versions

Everything is pinned in two places that must agree: `.gitlab-ci.yml`
(`variables:`) and `build/toolbox/Dockerfile`. The Go version also appears in
the three application Dockerfiles.

| What | Where |
|---|---|
| Go | `Dockerfile`, `build/distroless/Dockerfile`, `build/naive/Dockerfile`, `build/toolbox/Dockerfile`, `GO_IMAGE` |
| Tool images (Trivy, hadolint, golangci-lint, Checkov, gitleaks, kube-score, kubeconform, kustomize, Kaniko, crane, docker, glab) | `*_IMAGE` variables and the matching `FROM … AS` line in the toolbox |
| kind, kubectl binaries | `KIND_VERSION`/`KIND_SHA256`, `KUBECTL_VERSION`/`KUBECTL_SHA256`; toolbox `KIND_VERSION` and the kubectl `FROM` line |
| kind node image | `scripts/kind-up.sh` (`NODE_IMAGE`), `KUBERNETES_VERSION` in `.gitlab-ci.yml` and the Makefile |
| gotestsum | `GOTESTSUM_VERSION` in both files |

Procedure:

1. Find the new version and its digest:

   ```bash
   docker buildx imagetools inspect aquasec/trivy:<new-version> --format '{{.Manifest.Digest}}'
   ```

   For release binaries, take the SHA-256 from the project's published
   checksum file, not from a download you just made.
2. Change the tag **and** the digest together, in every place listed above.
3. Rebuild the toolbox and run everything:

   ```bash
   scripts/toolbox.sh make toolbox
   ```

   ```bash
   scripts/toolbox.sh make doctor lint test image scan validate
   ```

4. A new scanner version can report new findings. Fix them or suppress them
   under the policy above; do not pin back to avoid them.
5. While you are there, re-read every suppression's review date
   ([SECURITY.md](SECURITY.md#suppressions)). Checkov skips have no automatic
   expiry.
6. If the Go version or base image changed, re-run `make size-report` and
   update the numbers quoted in the README and SECURITY.md from the new
   `docs/evidence/image-size.txt`.

One commit per tool (`build: bump trivy to <version>`), so a bad update can be
reverted on its own.

## Cutting a release

1. `main` is green.
2. Tag and push to both remotes:

   ```bash
   git tag -a v1.2.3 -m "v1.2.3: <summary>"
   ```

   ```bash
   git push origin v1.2.3 && git push gitlab v1.2.3
   ```

3. The tag pipeline runs every stage again. `release-image` then gives the
   digest that passed the gates the tag `v1.2.3` in the registry (a
   registry-side retag with crane, not a rebuild), and `release` creates the GitLab
   release with notes generated by `scripts/release-notes.sh`.
4. Deploy with the `deploy-staging` button on the tag pipeline.

Only `vMAJOR.MINOR.PATCH` tags trigger the release jobs.
