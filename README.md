# orders-api-pipeline

**Status: in progress.** See [docs/PLAN.md](docs/PLAN.md) for what is done and what is not.

A small Go orders API used as the payload for a GitLab CI/CD pipeline that
builds a hardened container image, scans it (Trivy, Checkov, hadolint,
gitleaks, kube-score), blocks the pipeline on findings, and deploys it to
Kubernetes with kustomize. The application is deliberately small; the
pipeline, the image hardening and the security gates are the point.

The code is published on GitHub; a GitLab project runs the pipeline from the
same commits.

## Documentation

- [docs/PLAN.md](docs/PLAN.md): build plan and progress
- [docs/DECISIONS.md](docs/DECISIONS.md): decision log
- [docs/SETUP-GITLAB.md](docs/SETUP-GITLAB.md): creating the GitLab project and running the pipeline
- [docs/SECURITY.md](docs/SECURITY.md): what each control does and does not cover
- [docs/evidence/](docs/evidence/): raw command output behind every number

## License

[MIT](LICENSE)
