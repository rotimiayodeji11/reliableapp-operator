# Jenkins delivery contract

This directory models a production-safe delivery path for the ReliableApp operator. Jenkins builds one image, records its Git revision and local image ID, scans and tests that exact image, publishes it once, and deploys the registry digest rather than a mutable tag.

## Pipeline stages

1. Checkout and derive the full Git commit with `git rev-parse HEAD`.
2. Validate pinned tools, lint Go, run unit tests, and run the race detector.
3. Render Helm and Kustomize output, then validate both with kubeconform without contacting a live cluster.
4. Build the container image once with the Git commit as its tag and revision label.
5. Generate a CycloneDX SBOM and scan the same local image with Trivy.
6. Load the same image into an isolated Kind cluster and run E2E tests without rebuilding it.
7. When staging is requested, push the certified image and record the registry digest.
8. Deploy that digest as the staging candidate with Helm `--atomic` and wait for rollout.
9. Compare baseline and candidate performance, shadow divergence, error rate, and remaining error budget.
10. Require an authorized manual approval and a Jenkins production lock.
11. Record the current Helm revision, deploy the same digest to production, and run the post-deployment SLO gate.
12. If the post-deployment SLO gate fails, roll back to the revision recorded before deployment and capture diagnostics.

## Immutable artifact policy

The only `docker build` in the Jenkins path is the `Build immutable image` stage. `ci/image-security.sh`, `ci/kind-e2e.sh`, and `ci/publish-image.sh` fail when that image is missing; they never rebuild it. After the registry push, `evidence/published-image.txt` contains the digest reference used by staging and production.

`latest`, `workspace`, and other mutable deployment tags are rejected. The `controller:ci` value in Kustomize and GitHub chart testing is a local CI placeholder; Jenkins deployment always overrides it with the certified digest.

## Manifest validation

`ci/validate-manifests.sh` does not use `kubectl apply`, so it does not attempt API discovery at `localhost:8080`. It:

- regenerates controller manifests and rejects unreviewed generated drift;
- renders the Helm chart and Kustomize overlay locally;
- runs pinned kubeconform schema validation with strict parsing (schemas come from the public registry by default, or `KUBECONFORM_SCHEMA_LOCATION` can point to an approved mirror/local cache);
- reports missing schemas for custom APIs without contacting a cluster.

## Candidate versus canary

The current chart installs cluster-scoped RBAC and one leader-elected controller. It therefore deploys a fully isolated **staging candidate**, not a percentage-based production canary. A true controller canary would require release-scoped RBAC, separate watched namespaces and leader-election identities, or a traffic/control-plane routing design. The pipeline does not claim to split production traffic.

## Required Jenkins configuration

Credentials:

- `reliableapp-container-registry`: username/password credential.
- `reliableapp-staging-kubeconfig`: file credential.
- `reliableapp-production-kubeconfig`: file credential.
- `reliableapp-prometheus-token`: read-only secret text credential.

Plugins:

- Pipeline and Credentials Binding.
- Lockable Resources for the production deployment lock.

Environment variables supplied by the Jenkins job or managed environment:

- `PROMETHEUS_URL`
- `PROMETHEUS_STAGING_ERROR_RATE_QUERY`
- `PROMETHEUS_STAGING_ERROR_BUDGET_REMAINING_QUERY`
- `PROMETHEUS_PRODUCTION_ERROR_RATE_QUERY`
- `PROMETHEUS_PRODUCTION_ERROR_BUDGET_REMAINING_QUERY`
- `PROMETHEUS_ERROR_RATE_LIMIT`, default `0.01`
- `PROMETHEUS_ERROR_BUDGET_REMAINING_MINIMUM`, default `0.25`
- `SHADOW_QUERY`
- `SHADOW_DIVERGENCE_THRESHOLD`, default `0.05`
- `BASELINE_URL` and `CANDIDATE_URL` when the performance gate runs

Jenkins agents must provide the tools and versions declared in `ci/tool-versions.env`. `ci/validate-tools.sh` verifies them before source validation begins.

## Performance and reliability gates

`ci/performance-gate.sh` compares real baseline and candidate HTTP samples. `enforce` blocks regressions; `report-only` records threshold or Taurus failures without blocking; `disabled` skips the check.

The shadow gate requires exactly one numeric Prometheus result and fails when divergence exceeds its threshold. The SLO gate uses separate staging and production queries and fails closed unless both the error-rate and remaining-error-budget queries return exactly one numeric result within policy.

## Diagnostics and evidence

Evidence is written under `evidence/`, ignored by Git and archived by Jenkins. A failed Kind run exports cluster logs before deleting the cluster. Deployment failures capture Kubernetes events, Deployment details and controller logs.

## Local verification

```bash
bash -n ci/*.sh
git diff --check
helm lint dist/chart
helm template reliableapp-operator dist/chart \
  --set-string manager.image.repository=registry.example.invalid/reliableapp-operator \
  --set-string manager.image.tag="$(git rev-parse HEAD)"
make lint
make test
bash ci/validate-manifests.sh
```

Kind E2E additionally requires a working Docker daemon and Kind. Prometheus, shadow, registry and real deployment checks require their external services and approved Jenkins credentials.

## Rollback

Helm `--atomic` handles failures during an upgrade. A failure in the later post-deployment SLO gate invokes:

```bash
bash ci/rollback.sh RELEASE PREVIOUS_REVISION NAMESPACE
```

If no previous revision exists, Jenkins fails with a manual-intervention message rather than pretending rollback succeeded.
