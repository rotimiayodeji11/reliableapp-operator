#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/tool-versions.env"
for tool in git make go python3 docker kubectl helm kind jq curl golangci-lint syft trivy kubeconform; do
  command -v "$tool" >/dev/null || { echo "Missing Jenkins tool: $tool" >&2; exit 1; }
done

check_version_contains() {
  local tool="$1"
  local expected="$2"
  shift 2
  local output
  output="$("$@" 2>&1)" || {
    echo "Could not read $tool version" >&2
    exit 1
  }
  [[ "$output" == *"$expected"* ]] || {
    echo "Expected $tool $expected, got: $output" >&2
    exit 1
  }
}

helm_version="$(helm version --template '{{.Version}}')"
[[ "$helm_version" == "v${HELM_VERSION}" ]] || { echo "Expected Helm ${HELM_VERSION}, got ${helm_version}" >&2; exit 1; }
check_version_contains Kind "v${KIND_VERSION}" kind version
check_version_contains golangci-lint "${GOLANGCI_LINT_VERSION#v}" golangci-lint version
check_version_contains Syft "$SYFT_VERSION" syft version
check_version_contains Trivy "$TRIVY_VERSION" trivy --version
check_version_contains kubeconform "v${KUBECONFORM_VERSION#v}" kubeconform -v

required_go="$(awk '/^go / {print $2}' go.mod)"
actual_go="$(go env GOVERSION)"
actual_go="${actual_go#go}"
[[ "${actual_go%.*}" == "${required_go%.*}" ]] || {
  echo "Expected Go ${required_go%.*}.x, got $actual_go" >&2
  exit 1
}

echo "Required Jenkins tools are installed at the pinned versions"
