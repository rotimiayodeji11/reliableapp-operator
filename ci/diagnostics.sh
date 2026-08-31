#!/usr/bin/env bash
set -euo pipefail
kind_or_environment="${1:?Environment or Kind cluster is required}"
mkdir -p evidence
if [[ "$kind_or_environment" == kind ]]; then
  kind export logs --name "${2:?Kind cluster is required}" --output "evidence/kind-logs" || true
  exit 0
fi
release="${2:?Release is required}"
namespace="${3:?Namespace is required}"
kubectl -n "$namespace" get events --sort-by=.lastTimestamp > "evidence/${kind_or_environment}-events.txt" || true
kubectl -n "$namespace" describe deployment "$release-controller-manager" > "evidence/${kind_or_environment}-deployment.txt" || true
kubectl -n "$namespace" logs deployment/"$release-controller-manager" --all-containers --tail=500 > "evidence/${kind_or_environment}-controller.log" || true
