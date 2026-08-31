#!/usr/bin/env bash
set -euo pipefail
release="${1:?Release is required}"
revision="${2:?Helm revision is required}"
namespace="${3:?Namespace is required}"
helm rollback "$release" "$revision" --namespace "$namespace" --atomic --wait --timeout 10m
kubectl -n "$namespace" rollout status deployment/"$release-controller-manager" --timeout=5m
