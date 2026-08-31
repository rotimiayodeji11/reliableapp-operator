#!/usr/bin/env bash
set -euo pipefail
: "${PROMETHEUS_URL:?PROMETHEUS_URL is required}"
: "${PROMETHEUS_BEARER_TOKEN:?Prometheus credential is required}"
: "${SHADOW_QUERY:?SHADOW_QUERY must select baseline and candidate shadow metrics}"
: "${SHADOW_DIVERGENCE_THRESHOLD:=0.05}"

mkdir -p evidence
curl --fail --silent --show-error -G "$PROMETHEUS_URL/api/v1/query" \
  -H "Authorization: Bearer $PROMETHEUS_BEARER_TOKEN" --data-urlencode "query=$SHADOW_QUERY" > evidence/shadow-traffic.json
jq -e '.status == "success" and (.data.result | length == 1)' evidence/shadow-traffic.json >/dev/null || {
  echo 'Shadow query did not return exactly one successful result' >&2
  exit 1
}

divergence="$(jq -er '.data.result[0].value[1] | tonumber' evidence/shadow-traffic.json)"
if awk -v value="$divergence" -v threshold="$SHADOW_DIVERGENCE_THRESHOLD" 'BEGIN { if (value < 0 || value > threshold) exit 1 }'; then
  printf 'divergence=%s\nthreshold=%s\n' "$divergence" "$SHADOW_DIVERGENCE_THRESHOLD" > evidence/shadow-traffic.txt
  echo 'Shadow divergence is within the configured threshold' >&2
else
  printf 'divergence=%s\nthreshold=%s\n' "$divergence" "$SHADOW_DIVERGENCE_THRESHOLD" > evidence/shadow-traffic.txt
  echo "Shadow divergence ${divergence} exceeds threshold ${SHADOW_DIVERGENCE_THRESHOLD}" >&2
  exit 1
fi

echo 'Shadow comparison queried Prometheus read-only; no traffic was mutated' >> evidence/shadow-traffic.txt
