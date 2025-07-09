# Metadata Store Test Automation

As-is, `./run.sh` it will deploy a small RabbitMQ cluster to Kubernetes
in a loop, and perform a few operations on it:
- import metadata
- restart the cluster
- stop/start a single node

and so on. It will perform these operations for aech file matching '*.json.gz'.
It will perform these operations with and without Khepri.

Once the tests completed, `./summary.sh` will print a summary of the results as CSV.

`rabbitmq.yaml` should be updated for more realistic tests. In particular,
more CPU cores, more RAM and faster storage class are needed for the largest
definitions files.
