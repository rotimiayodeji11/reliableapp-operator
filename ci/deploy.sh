#!/usr/bin/env bash
set -euo pipefail
environment="${1:?Environment is required}"
release="${2:?Release is required}"
namespace="${3:?Namespace is required}"
image="${4:?Image is required}"
chart="${5:?Chart path is required}"

case "$image" in
  *@sha256:*)
    digest="${image##*@sha256:}"
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || {
      echo "Image $image has an invalid sha256 digest" >&2
      exit 1
    }
    image_repository="$image"
    image_tag=""
    ;;
  *:*)
    image_repository="${image%:*}"
    image_tag="${image##*:}"
    [[ "$image_tag" =~ ^[0-9a-f]{40,64}$ ]] || {
      echo "Deployments require an immutable registry digest or full Git commit tag; got $image_tag" >&2
      exit 1
    }
    ;;
  *)
    echo "Image $image has no immutable digest or tag" >&2
    exit 1
    ;;
esac

mkdir -p evidence
helm upgrade --install "$release" "$chart" --namespace "$namespace" --create-namespace \
  --set-string manager.image.repository="$image_repository" --set-string manager.image.tag="$image_tag" \
  --atomic --wait --timeout 10m --history-max 10 2>&1 | tee "evidence/helm-${environment}-deploy.log"
kubectl -n "$namespace" rollout status deployment/"$release-controller-manager" --timeout=5m
kubectl -n "$namespace" get deployment,pods -o wide > "evidence/${environment}-rollout.txt"
