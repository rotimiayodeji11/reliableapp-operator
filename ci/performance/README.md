# Performance gate baseline

This directory contains a versioned Taurus baseline-versus-candidate smoke test. The two URLs must point at isolated, non-production targets that expose `/healthz`. Run the pipeline with `PERFORMANCE_GATE=report-only` while calibrating the service, then use `enforce` once the latency and failure criteria are accepted by the service owner.

When Taurus is installed on the Jenkins agent, the versioned `taurus.yml` scenario runs with deliberately low concurrency. The Python comparison remains the required gate and samples the same `/healthz` endpoints. This is a promotion signal, not a capacity benchmark. Store performance artifacts with the Jenkins build evidence. A shadow comparison is separate: `ci/shadow-traffic-gate.sh` makes a read-only Prometheus query for already-recorded baseline and candidate metrics. It does not mirror or replay requests, alter routing, or mutate production traffic.
