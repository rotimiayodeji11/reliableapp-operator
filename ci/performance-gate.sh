#!/usr/bin/env bash
set -euo pipefail

mode="${1:-report-only}"
case "$mode" in
  report-only|enforce|disabled) ;;
  *) echo "Unknown performance gate mode: $mode" >&2; exit 1 ;;
esac
[[ "$mode" == disabled ]] && exit 0
[[ -n "${BASELINE_URL:-}" && -n "${CANDIDATE_URL:-}" ]] || {
  echo 'BASELINE_URL and CANDIDATE_URL are required when the performance gate is enabled' >&2
  [[ "$mode" == report-only ]] && exit 0
  exit 1
}

mkdir -p evidence

if command -v bzt >/dev/null 2>&1; then
  if ! BASELINE_URL="$BASELINE_URL" CANDIDATE_URL="$CANDIDATE_URL" \
    bzt ci/performance/taurus.yml -o settings.artifacts-dir=evidence/taurus 2>&1 | tee evidence/performance-gate.log; then
    echo 'Taurus smoke run failed' >&2
    if [[ "$mode" == enforce ]]; then
      exit 1
    fi
    echo 'Report-only mode recorded the Taurus failure without blocking promotion' >&2
  fi
fi

PERF_ERROR_RATE_LIMIT="${PERF_ERROR_RATE_LIMIT:-0.02}"
PERF_LATENCY_REGRESSION_LIMIT="${PERF_LATENCY_REGRESSION_LIMIT:-0.25}"

python3 - "$BASELINE_URL" "$CANDIDATE_URL" "$PERF_ERROR_RATE_LIMIT" "$PERF_LATENCY_REGRESSION_LIMIT" "$mode" <<'PY'
import json, statistics, sys, time, urllib.error, urllib.request

baseline_url, candidate_url, error_limit, latency_limit, mode = sys.argv[1:6]
baseline_url = baseline_url.rstrip('/') + '/healthz'
candidate_url = candidate_url.rstrip('/') + '/healthz'
error_limit = float(error_limit)
latency_limit = float(latency_limit)


def sample(url, repeats=10):
    latencies = []
    errors = 0
    for _ in range(repeats):
        start = time.perf_counter()
        try:
            req = urllib.request.Request(url, method='GET')
            with urllib.request.urlopen(req, timeout=10) as resp:
                status = resp.status
        except Exception:
            status = 0
        elapsed_ms = (time.perf_counter() - start) * 1000
        latencies.append(elapsed_ms)
        if status < 200 or status >= 400:
            errors += 1
    return {
        'samples': repeats,
        'error_rate': errors / repeats,
        'avg_latency_ms': statistics.fmean(latencies),
        'p95_latency_ms': sorted(latencies)[max(0, int(0.95 * len(latencies)) - 1)],
    }

baseline = sample(baseline_url)
candidate = sample(candidate_url)

baseline_latency = baseline['avg_latency_ms'] or 1.0
candidate_latency = candidate['avg_latency_ms'] or 1.0
latency_delta = (candidate_latency - baseline_latency) / baseline_latency if baseline_latency > 0 else 0.0
error_delta = candidate['error_rate'] - baseline['error_rate']

result = {
    'baseline': baseline,
    'candidate': candidate,
    'latency_regression_ratio': latency_delta,
    'error_rate_regression': error_delta,
    'thresholds': {
        'max_error_rate_regression': error_limit,
        'max_latency_regression_ratio': latency_limit,
    },
    'mode': mode,
    'within_threshold': latency_delta <= latency_limit and error_delta <= error_limit,
}

with open('evidence/performance-gate.json', 'w', encoding='utf-8') as fh:
    json.dump(result, fh, indent=2)

summary = (
    f"baseline_error_rate={baseline['error_rate']:.4f} "
    f"candidate_error_rate={candidate['error_rate']:.4f} "
    f"baseline_avg_latency_ms={baseline_latency:.2f} "
    f"candidate_avg_latency_ms={candidate_latency:.2f} "
    f"latency_regression_ratio={latency_delta:.4f} "
    f"error_rate_regression={error_delta:.4f}"
)
with open('evidence/performance-gate.txt', 'w', encoding='utf-8') as fh:
    fh.write(summary + '\n')

if latency_delta > latency_limit or error_delta > error_limit:
    print(summary, file=sys.stderr)
    if mode == 'enforce':
        raise SystemExit(1)

print(summary)
PY

if [[ "${mode}" == "report-only" ]]; then
  echo 'Performance gate is in report-only mode; the comparison was recorded but promotion was not blocked' >&2
fi
