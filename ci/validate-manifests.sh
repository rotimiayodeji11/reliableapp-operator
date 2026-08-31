#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/tool-versions.env"

schema_location="${KUBECONFORM_SCHEMA_LOCATION:-default}"

mkdir -p evidence

command -v helm >/dev/null 2>&1 || { echo 'helm is required for manifest validation' >&2; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo 'kubectl is required for manifest validation' >&2; exit 1; }

# Regenerate source manifests and the consolidated installer to ensure generated
# deployment artifacts remain consistent with the reviewed source.
make build-installer

git diff --exit-code -- config/crd/bases config/rbac config/manager/kustomization.yaml dist/install.yaml || {
  echo 'Generated manifests changed; regenerate them in the source branch and review the result.' >&2
  exit 1
}

if grep -Eq 'image: .*:(latest|workspace)([[:space:]]|$)' dist/install.yaml; then
  echo 'Generated installer contains a mutable image tag' >&2
  exit 1
fi

# Validate the rendered output without contacting a live Kubernetes API. This is
# deterministic on Jenkins agents that do not have a cluster or kubeconfig.
helm template reliableapp-operator dist/chart \
  --set-string manager.image.repository="${IMAGE_REPOSITORY:-registry.example.invalid/reliableapp-operator}" \
  --set-string manager.image.tag="${GIT_COMMIT:-local}" > evidence/helm-rendered.yaml

# kustomize does not call the API server; it only renders local YAML.
KUBECONFIG=/dev/null kubectl kustomize config/default > evidence/kustomize-default.yaml

# Ensure generated output exists and contains Kubernetes resources before continuing.
[[ -s evidence/helm-rendered.yaml ]] || { echo 'helm template produced no output' >&2; exit 1; }
[[ -s evidence/kustomize-default.yaml ]] || { echo 'kustomize produced no output' >&2; exit 1; }

grep -Eq 'kind:\s+(Deployment|CustomResourceDefinition|Service)' evidence/helm-rendered.yaml || {
  echo 'Rendered Helm output does not contain Kubernetes resources' >&2
  exit 1
}

grep -Eq 'kind:\s+(Deployment|CustomResourceDefinition|Service)' evidence/kustomize-default.yaml || {
  echo 'Rendered kustomize output does not contain Kubernetes resources' >&2
  exit 1
}

# Validate against Kubernetes OpenAPI schemas without contacting a live cluster.
# By default kubeconform downloads schemas from its public registry. Production
# Jenkins agents can set KUBECONFORM_SCHEMA_LOCATION to an approved internal
# schema mirror or a pre-populated local directory.
command -v kubeconform >/dev/null 2>&1 || { echo 'kubeconform is required for schema validation' >&2; exit 1; }

kubeconform -strict -summary -ignore-missing-schemas \
  -kubernetes-version "$ENVTEST_K8S_VERSION" \
  -schema-location "$schema_location" \
  -output json evidence/helm-rendered.yaml 2>&1 | tee evidence/kubeconform-helm.log || {
  echo 'Helm-rendered manifest schema validation failed' >&2
  exit 1
}

kubeconform -strict -summary -ignore-missing-schemas \
  -kubernetes-version "$ENVTEST_K8S_VERSION" \
  -schema-location "$schema_location" \
  -output json evidence/kustomize-default.yaml 2>&1 | tee evidence/kubeconform-kustomize.log || {
  echo 'Kustomize-rendered manifest schema validation failed' >&2
  exit 1
}

printf 'Rendered manifests validated with kubeconform; no live cluster contact was required.\nSchema location: %s\nKubernetes version: %s\n' \
  "$schema_location" "$ENVTEST_K8S_VERSION" > evidence/manifest-validation.txt
