#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/tool-versions.env"
cluster="${1:?Kind cluster name is required}"
image="${2:?Image reference is required}"

# Ensure failure diagnostics are captured before cleanup.
cleanup() {
  exit_code=$?
  trap - EXIT
  if (( exit_code != 0 )); then
    bash ci/diagnostics.sh kind "$cluster" || true
  fi
  kind delete cluster --name "$cluster" >/dev/null 2>&1 || true
  exit "$exit_code"
}
trap cleanup EXIT

kind delete cluster --name "$cluster" >/dev/null 2>&1 || true
kind create cluster --name "$cluster" --image "$KIND_NODE_IMAGE" --wait 120s

docker image inspect "$image" >/dev/null 2>&1 || {
  echo "Image $image was not built before Kind E2E; build it once and reuse it for all stages" >&2
  exit 1
}

kind load docker-image "$image" --name "$cluster"
KIND_CLUSTER="$cluster" \
  MANAGER_IMAGE="$image" \
  MANAGER_IMAGE_PRELOADED=true \
  go test -tags=e2e ./test/e2e/ -v -ginkgo.v
