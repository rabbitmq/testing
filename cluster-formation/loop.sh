#!/usr/bin/env bash

set -x

iterations=${1:?"Usage: $0 <iterations>"}

mkdir -p output

for i in $(seq $iterations); do
    mkdir -p output/$i

    while ! kubectl get pods -o name | grep -c server | grep '^0$'; do
        echo "There are still pods running. Waiting..."
        sleep 5
    done

    # deploy
    kubectl apply -f rabbitmq/

    sleep 10 # make sure pods are created
    # wait for pods to be ready
    kubectl wait --for=condition=Ready pod --all --timeout=300s

    for c in $(kubectl get rmq -o name); do
        cluster=$(echo $c | sed s/rabbitmqcluster.rabbitmq.com\\///)
        mkdir -p output/$i/$cluster

        kubectl exec -c rabbitmq -it $cluster-server-0 -- rabbitmqctl cluster_status 2>&1 | grep -A 12 'Running Nodes' > output/$i/$cluster/status.log

        for p in $(kubectl get pods -o name | grep ^pod/$cluster); do
            pod=$(echo $p | sed s/pod\\///)
            kubectl exec -ti $pod -c rabbitmq -- rabbitmqctl eval 'length(rabbit_nodes:list_running()).' | sed s/[^0-9]// > output/$i/$cluster/$pod.nodes
            
        kubectl get pod -l=app.kubernetes.io/name=$cluster > output/$i/$cluster/get_pods.txt

        if [[ $(kubectl get pod "$pod" | grep server | awk '{print $4}') != 0 ]]; then
            # There was a container restart => get logs from previous container
            kubectl logs -c rabbitmq --previous "$pod" > output/$i/$cluster/$pod.log
        fi

            kubectl logs -c rabbitmq $pod >> output/$i/$cluster/$pod.log

        done

        # check if all nodes agree
        cat output/$i/$cluster/*.nodes | sort | uniq | wc -l | grep -q 1 || echo "Nodes disagree! Iteration $i failed"

        kubectl delete rmq $cluster
        kubectl wait --for=delete pods -l=app.kubernetes.io/name=$cluster --timeout=5m
        kubectl delete pod -l=app.kubernetes.io/name=$cluster --force
    done

    # all good - delete
    kubectl delete -f rabbitmq/

done

