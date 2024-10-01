## Chaos Tests

Examples of chaos tests using https://chaos-mesh.org/

### Chaos Mesh

Chaos Mesh is already installed in our cluster, so this examples can be used right away.
If you don't have it installed, that's the first step.

### Dedicated Namespace

In our environment, Chaos Mesh is configured to only allow injecting failures in the `chaos-tests` namespace.
This prevents accidentally breaking other tests.

### How To Use It

1. Deploy a cluster to `chaos-tests`
2. Adjust the example if necessary (in particular, label selectors)
3. Apply the chaos tests

You can monitor the execution with:
1. `kubectl describe <resource> <name>`, eg. `kubectl describe networkchaos.chaos-mesh.org partition-0-from-1`
2. Chaos Mesh dashboard: `kubectl -n chaos-mesh port-forward svc/chaos-dashboard 2333` and then http://localhost:2333/#/dashboard
