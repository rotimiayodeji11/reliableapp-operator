# Checkout API CrashLoopBackOff

## Summary

A rollout configured the checkout API liveness probe to query port 8080 while
the application served traffic on port 80. Kubernetes repeatedly terminated
both healthy replicas, reducing Deployment availability to zero.

## Impact

- The Deployment reported 0 of 2 available replicas.
- Both Pods entered `CrashLoopBackOff` and accumulated restarts.
- The simulated checkout request path was unavailable until rollback.

## Detection and diagnosis

1. Confirmed the cluster context and affected namespace.
2. Observed 0 of 2 available replicas and increasing restart counts.
3. Used `kubectl describe pod` to find repeated liveness probe failures on
   port 8080.
4. Used `kubectl logs --previous` to confirm nginx started normally and then
   received `SIGQUIT`, exiting cleanly with code 0.

## Mitigation

Rolled the Deployment back from revision 2 to the known-good revision 1. The
rollout completed with 2 of 2 replicas ready, zero new restarts, and a
successful HTTP response.

## Root cause

The health endpoint port was configured independently from the application
listener. Kubernetes accepted the valid YAML but could not determine that no
process listened on the configured probe port.

## Corrective actions

- Define the controller health port once in Helm values.
- Use a named port for both liveness and readiness probes.
- Validate the allowed TCP port range with a Helm values schema.
- Run a CI regression check that renders a non-default port and verifies the
  bind address, container port, and probes remain connected.
- Record a release identifier and change cause for future rollouts.
