## Getting started

This folder helps to run the same workload against multiple RabbitMQ instances at the same time.
The instances can differ in many ways: version (OCI image), configuration, Erlang flags, etc.

There is currently the main test suite, which runs a dozen AMQP 0.9.1 workloads one after another.
Those include fast publishing and consuming, publishing without consuming, consuming without publishing
and so on. We use it to compare performance of different versions, validate improvements or check for regressions.

You can easily make small modifications to the deployment and/or workload. However, sometimes you may want
to change something that is currently not configurable, in which case, you can either make it configurable
or copy the folder and make test-specific adjustments.

On a high level, this repository provides the following:
* a `RabbitmqCluster` deployment template
* a client deployment template (it can use [perf-test](https://perftest.rabbitmq.com/), [stream-perf-test](https://rabbitmq.github.io/rabbitmq-stream-java-client/stable/htmlsingle/#the-performance-tool) or [emqtt-bench](https://github.com/emqx/emqtt-bench))
* a set of configuration/value files to render the templates

## Prerequisites

The templates use [YTT](https://carvel.dev/ytt/), so you need to install it:
```
$ brew tap vmware-tanzu/carvel
$ brew install ytt
```

The tests are Kubernetes based so you need `kubectl` pointed at a Kubernetes cluster.

If you want to point `kubectl` at our shared Kubernetes cluster, run this:
```
gcloud container clusters get-credentials CLUSTER_NAME --region europe-west2-a --project PROJECT_NAME
```

Lastly, the perf-test template relies on perf-test synchronisation mechanism to ensure all tests start at the same time
(otherwise, given for example a Kubernetes node scale-out, some tests could start a few minutes later). For this mechanism to work,
you need permissions in the namespace you are deploying to.
```
ytt --data-value namespace=MY_NAMESPACE -f permissions.yaml | kubectl apply -f -
```

Note: in our cluster existing namespaces already have these permissions. This is a one-off thing you need for new namespaces only.

## Running Existing Tests

To run an existing test you may do something like this:

```
# use the main tests folder
$ cd main

# generate all permutations
$ ./generate.sh scenario-qq.yaml

# deploy the clusters
$ kubectl apply -f rabbitmq/

# wait for the clusters to be ready; if you want, you can run this command - it will exit once they are all ready
$ kubectl wait --timeout=7200s --for=condition=Ready=true pod --all

# deploy perf-test
$ kubectl apply -f client/
```

## Cleanup

To delete all perf-test instances and all clusters, run:

```
$ kubectl delete -f rabbitmq/
$ kubectl delete -f client/
```

or
```
$ kubectl delete deployments --all
$ kubectl delete rmq --all
```

The advantage of the latter is that if you regenerated the test with new values, YAML files may not describe all the existing clusters so some may not be deleted of you `kubectl delete -f ...`
The downside is that it will delete all deployments and RabbitMQ clusters in the current namespace - make sure that's what you want (but likely yes, if you are just running tests)

## Defining a New Scenario

Let's say you are working on a branch and want to check the impact of that branch compared to `main`.
There is a common test suite that excercises different aspects (slow publishers, fast publishers,
publishers without consumers, consumers without publishers, fanout, etc). To run this suite against `main`
and your branch, you can:

1. go the the `main` folder
2. copy (or just modify) an existing sceanario, probably by changing the tag; we build OCI images on every commit,
   you will probably want to use branch tag, eg. `pivotalrabbitmq/rabbitmq:khepri-otp-max` would be a tag for the
   most recent (successful!) `khepri` build; find more tags here: https://hub.docker.com/r/pivotalrabbitmq/rabbitmq/tags
3. You can adjust the settings, for example if your change should only affect quorum queues, add `-qq` to `env_flags`
4. Follow the steps above (`./generate my-scenario.yaml; kubectl apply -f rabbitmq client`)

Once you are done, you need to decide whether your test is worth pushing to the repo. If there is nothing special about it,
and it was just a matter of testing a specific branch that is now merged, you can just delete/checkout/revert the scenario file.
If it is something that could be reused, you can just push a new scenario file.

Here's a sample scenario file comparing QQs between `main` and 3.11.7:
```yaml
#@data/values
---
msg_sizes: [12, 100, 1000, 5000, 25000, 100000]

clusters:
  - name: v3-11-7
    replicas: 3
    image: rabbitmq:3.11.7-management
    env_flags: -qq
  - name: main
    replicas: 3
    image: pivotalrabbitmq/rabbitmq:main-otp-max-bazel
    env_flags: -qq
```

This example defines 2 RabbitMQ clusters (named `v3-11-7` and `main`) that use two different images.
Note, Kubernetes resource names need to be valid DNS names, so you can't use dots in the `name` filed and the name can't
start with a digit for example, hence `v3-11-7`.

On top of that, we define 6 message sizes. When you run `./generate.sh` you'll actually get 12 different clusters.
The message size will be appended to the cluster name, so you'll get `main-s12`, `main-s100` and so on.

Here's another scenario example. In this case we use the same image but we set different `--queue-args` to change the queue type.

```yaml
clusters:
  - name: cqv1
    replicas: 1
    image: pivotalrabbitmq/rabbitmq:main-otp-max-bazel
    env_flags: -qa x-queue-version=1
  - name: cqv2
    replicas: 1
    image: pivotalrabbitmq/rabbitmq:main-otp-max-bazel
    env_flags: -qa x-queue-version=2
  - name: qq
    replicas: 1
    image: pivotalrabbitmq/rabbitmq:main-otp-max-bazel
    env_flags: -qq
```

You can have multiple scenario files in the same folder. By default, `./generate.sh` will use `scenario.yaml` but you can pass any other file as an argument,
for example:
```
./generate.sh scenario-versions.yaml
```

Simirily, by default `./generate.sh` will use `script.sh` as the workload script, but you can use a different one:
```
./generate.sh scenario-versions.yaml custom-script.sh
```

## Defining a New Script

For quick tests, you can just edit `script.sh` and then decide whether you want to push the change (eg. to add a new test
to the suite we run most commonly), push it as a new file (`myscript.sh`) or just reset the repo.

`script.sh` is a good starting point either way. Most often you just want to edit the `main()` function, to define the tests you want.
Later on, there are simply helpers that pre-define flags, for example to expose metrics with some additional tags (this allows us
to later filter by message size for example).

## Links

* Our OCI images: https://registry.hub.docker.com/r/pivotalrabbitmq/rabbitmq/tags
* Our Grafana deployment: https://grafana.lionhead.rabbitmq.com/ (there's also an older Kubernetes cluster at https://grafana.rabbitmq.com/)
* Most often you'll want the `RabbitMQ Performance Tests` dashboard: https://grafana.rabbitmq.com/d/1OSIKB4Vk/rabbitmq-performance-tests?orgId=1
* Logs (logs from all deployments are always collected): https://grafana.lionhead.rabbitmq.com/explore
