

Smoke tests run automatically on every sync.
```sh
kubectl logs -n voting -l app.kubernetes.io/component=test --tail=200 -f
# or
kubectl get jobs -n voting
kubectl describe job -n voting voting-app-api-smoke-internal


# load
# Once the job appears
kubectl get job -n voting voting-app-api-load -w

# Follow the k6 output in real time
kubectl logs -n voting job/voting-app-api-load -f


kubectl top pod -n voting
kubectl get pod -n voting -w

```