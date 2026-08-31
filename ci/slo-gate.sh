#!/usr/bin/env bash
set -euo pipefail

environment="${1:?Environment is required (staging or production)}"
: "${PROMETHEUS_URL:?PROMETHEUS_URL Jenkins environment variable is required}"
: "${PROMETHEUS_BEARER_TOKEN:?Prometheus credential is required}"
case "$environment" in
  staging)
    error_rate_query="${PROMETHEUS_STAGING_ERROR_RATE_QUERY:?PROMETHEUS_STAGING_ERROR_RATE_QUERY must be configured by Jenkins}"
    error_budget_query="${PROMETHEUS_STAGING_ERROR_BUDGET_REMAINING_QUERY:?PROMETHEUS_STAGING_ERROR_BUDGET_REMAINING_QUERY must be configured by Jenkins}"
    ;;
  production)
    error_rate_query="${PROMETHEUS_PRODUCTION_ERROR_RATE_QUERY:?PROMETHEUS_PRODUCTION_ERROR_RATE_QUERY must be configured by Jenkins}"
    error_budget_query="${PROMETHEUS_PRODUCTION_ERROR_BUDGET_REMAINING_QUERY:?PROMETHEUS_PRODUCTION_ERROR_BUDGET_REMAINING_QUERY must be configured by Jenkins}"
    ;;
  *)
    echo "Unsupported SLO environment: $environment" >&2
    exit 1
    ;;
esac
error_rate_limit="${PROMETHEUS_ERROR_RATE_LIMIT:-0.01}"
error_budget_minimum="${PROMETHEUS_ERROR_BUDGET_REMAINING_MINIMUM:-0.25}"

mkdir -p evidence

query_value() {
  local query="$1"
  local output="$2"

  curl --fail --silent --show-error -G "$PROMETHEUS_URL/api/v1/query" \
    -H "Authorization: Bearer $PROMETHEUS_BEARER_TOKEN" \
    --data-urlencode "query=$query" > "$output"

  jq -e '.status == "success" and (.data.result | length == 1)' "$output" >/dev/null || {
    echo "Prometheus query did not return exactly one successful result" >&2
    return 1
  }
  jq -er '.data.result[0].value[1] | tonumber' "$output"
}

error_rate="$(query_value "$error_rate_query" "evidence/prometheus-${environment}-error-rate.json")"
error_budget_remaining="$(query_value "$error_budget_query" "evidence/prometheus-${environment}-error-budget.json")"

awk -v value="$error_rate" -v limit="$error_rate_limit" \
  'BEGIN { if (value < 0 || value > limit) exit 1 }' || {
    echo "Error rate $error_rate exceeds limit $error_rate_limit" >&2
    exit 1
  }

awk -v value="$error_budget_remaining" -v minimum="$error_budget_minimum" \
  'BEGIN { if (value < minimum || value > 1) exit 1 }' || {
    echo "Remaining error budget $error_budget_remaining is below minimum $error_budget_minimum" >&2
    exit 1
  }

printf 'error_rate=%s\nerror_rate_limit=%s\nerror_budget_remaining=%s\nerror_budget_minimum=%s\n' \
  "$error_rate" "$error_rate_limit" "$error_budget_remaining" "$error_budget_minimum" \
  > "evidence/slo-gate-${environment}.txt"
