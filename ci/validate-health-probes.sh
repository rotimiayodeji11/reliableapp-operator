#!/usr/bin/env bash
set -euo pipefail

chart="${1:-dist/chart}"
test_port=18081
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

helm template reliableapp-operator "$chart" \
  --show-only templates/manager/manager.yaml \
  --set-string manager.image.repository=registry.example.invalid/reliableapp-operator \
  --set-string manager.image.tag=probe-validation \
  --set manager.health.port="$test_port" > "$rendered"

grep -Fq -- "- --health-probe-bind-address=:$test_port" "$rendered" || {
  echo 'Manager health bind address does not use manager.health.port' >&2
  exit 1
}

grep -Fq "containerPort: $test_port" "$rendered" || {
  echo 'Health container port does not use manager.health.port' >&2
  exit 1
}

[[ "$(grep -Fc 'port: health' "$rendered")" -eq 2 ]] || {
  echo 'Liveness and readiness probes must both use the named health port' >&2
  exit 1
}

if helm lint "$chart" --set manager.health.port=70000 >/dev/null 2>&1; then
  echo 'Chart accepted an invalid health port outside the TCP port range' >&2
  exit 1
fi

printf 'Health probe wiring and port validation passed.\n'
