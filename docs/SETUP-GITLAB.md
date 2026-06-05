# GitLab setup

The code is published on GitHub (`origin`). GitLab runs the pipeline from the
same commits through a second remote (`gitlab`). These are the one-time steps
to connect the two and get a first green pipeline.

Replace `abhichandra-v` with your GitLab username if it differs.

## 1. Create the GitLab project

1. On gitlab.com: **New project → Create blank project**.
2. Project name `orders-api-pipeline`, visibility **Public**.
3. **Untick** "Initialize repository with a README" (the history comes from
   this repo).

Or with the CLI (`glab auth login` first):

```bash
glab repo create abhichandra-v/orders-api-pipeline --public --defaultBranch main
```

## 2. Check the project settings

**Settings → General → Visibility, project features, permissions**

- Container registry: **enabled**. `build-image` pushes to it.
- CI/CD: **enabled**.

**Settings → CI/CD → Runners**

- "Instance runners" is **enabled for this project**. The pipeline uses the
  `saas-linux-small-amd64` shared runners; no tags are needed.
- If GitLab shows "validate your account", do it. New accounts must verify
  (phone or card) before shared runners will pick up jobs. Until then every
  job sits in *pending*.

**Settings → Repository → Protected branches / Protected tags**

- `main` is protected by default. Add a protected tag pattern `v*`, so
  protected variables are available to release pipelines.

## 3. Add the remotes and push

```bash
git remote add origin git@github.com:abhichandra-v/orders-api-pipeline.git
```

```bash
git remote add gitlab git@gitlab.com:abhichandra-v/orders-api-pipeline.git
```

```bash
git push -u origin main --tags
```

```bash
git push gitlab main --tags
```

Pushing the tags starts one tag pipeline per tag (`v0.1.0`, `v0.5.0`,
`v1.0.0`) in addition to the `main` branch pipeline. That is expected; each
one also runs the `release` jobs.

## 4. Confirm the pipeline

```bash
glab ci status --repo abhichandra-v/orders-api-pipeline
```

or **Build → Pipelines** in the UI. Expected on `main`:

| Stage | Jobs | Notes |
|---|---|---|
| lint | `go-lint`, `hadolint` | |
| test | `go-test` | Coverage shows in the pipeline; tests under the **Tests** tab |
| build | `build-image` | Pushes `:<short-sha>` and `:main` to the registry |
| scan | `trivy-fs`, `trivy-config`, `trivy-image`, `sbom`, `checkov`, `gitleaks`, `render-manifests`, `kube-score`, `kubeconform` | Any finding fails the pipeline |
| deploy-test | `deploy-test` | kind cluster inside the job |
| deploy | `deploy-staging` | Manual; skips cleanly without `KUBECONFIG_B64` |
| release | `release-image`, `release` | Tag pipelines only |

Then check **Deploy → Container registry**: one repository with a
`:<short-sha>` and a `:main` tag.

If a job fails, open it, copy the log and compare with
[RUNBOOK.md](RUNBOOK.md) ("Triaging a failed scan").

## 5. CI/CD variables

None are required for a green pipeline: registry credentials come from the
built-in job token (`CI_REGISTRY_USER` / `CI_REGISTRY_PASSWORD`).

Optional, for the manual staging deploy (**Settings → CI/CD → Variables**):

| Key | Value | Flags |
|---|---|---|
| `KUBECONFIG_B64` | `base64 -w0 < staging-kubeconfig.yaml` | **Masked**, **Protected**, not expanded |

Use a kubeconfig for a service account that can only manage the `orders`
namespace, not a cluster-admin one. Without the variable, `deploy-staging`
prints a notice and exits 0.

## 6. Pipeline badge

After the first pipeline, the badge URL in the README resolves:

```
https://gitlab.com/abhichandra-v/orders-api-pipeline/badges/main/pipeline.svg
```

## 7. Evidence to capture

Save these under `docs/evidence/screenshots/` (names are referenced from the
README):

| File | What |
|---|---|
| `pipeline-green.png` | The `main` pipeline graph, all stages green |
| `pipeline-gate-blocked.png` | The `demo/vulnerable-base` pipeline, `trivy-image` red |
| `registry.png` | The container registry tag list |

To produce the blocked pipeline, push the demo branch (do **not** merge it):

```bash
git push gitlab demo/vulnerable-base
```

Save the failing `trivy-image` job log as
`docs/evidence/gate-blocks-vulnerable-image-gitlab.txt`.

## Keeping the two remotes in sync

Push to both. There is no mirroring configured, so nothing happens on GitLab
until you push there:

```bash
git push origin main --tags && git push gitlab main --tags
```
