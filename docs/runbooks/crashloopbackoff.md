# CrashLoopBackOff runbook

## User-impact check

1. Acknowledge the alert and record its start time.
2. Confirm the named cluster, namespace, Deployment, and service owner.
3. Check desired versus available replicas, restart rate, request errors,
   latency, traffic, saturation, and error-budget burn.

## Triage

```bash
kubectl config current-context
kubectl get deployment,pods --namespace <namespace> --output=wide
kubectl describe pod <pod> --namespace <namespace>
kubectl logs <pod> --namespace <namespace> --container <container> --previous
kubectl rollout history deployment/<deployment> --namespace <namespace>
```

Compare unhealthy Pods with a healthy replica when one exists. Correlate the
first failure with recent releases, configuration changes, node events, and
dependency failures. Do not repeatedly restart Pods without identifying what
will change.

## Mitigation

For a confirmed bad rollout with a known-good revision and appropriate change
authority:

```bash
kubectl rollout undo deployment/<deployment> --namespace <namespace> --to-revision=<revision>
kubectl rollout status deployment/<deployment> --namespace <namespace> --timeout=120s
```

Follow the service-specific deployment system and approval policy in a real
environment. Escalate if no safe rollback exists or the error budget is
burning rapidly.

## Recovery criteria

- Desired and available replicas match.
- Restart rate stops increasing.
- Functional requests succeed.
- Error rate and latency return to their normal range.
- Error-budget burn returns below the alert threshold.

Keep the incident open for an agreed stability window, communicate recovery,
and create corrective actions with owners and due dates.
