#!/bin/bash

trap "exit" SIGINT SIGTERM

AMQP_PERF_TEST_JAR=${PERF_TEST_JAR:-"/perf_test/perf-test.jar"}
STREAM_PERF_TEST_JAR=${PERF_TEST_JAR:-"/stream_perf_test/stream-perf-test.jar"}
RABBITMQ_SERVICE=${RABBITMQ_SERVICE:-localhost}
RABBITMQ_USER=${RABBITMQ_USER:-guest}
RABBITMQ_PASS=${RABBITMQ_PASS:-guest}

MSG_SIZE=${MSG_SIZE:-12}

TIME_PER_TEST=300

# the test(s) to run
main() {
    # publish and consume
    stream_perf_test one_fast -st one_fast
    delete_all_queues
    # publish only
    stream_perf_test publish_only -y 0 -st publish_then_consume
    # consume only
    stream_perf_test consume_only -x 0 -o first -st publish_then_consume
}

##
## HELPERS (hopefully no need to change anything there)
##

# run perf-test with the provided flags and all the necessary boilerplate
# note - by default we connect to server-0 for consistency between envs and tests
# this is bad for some tests; remove `-server-0.${RABBITMQ_SERVICE}-nodes` if you don't want that
perf_test() {
    WORKLOAD_NAME=${1}
    shift

    # connect to server-0 for consistency between environments and test runs (connection-queue locality)
    # expose Prometheus metrics with additional tags for filtering in the dashboard
    # producer random startup delay to avoid batches of messages being sent at the same time
    java -jar $AMQP_PERF_TEST_JAR $* -s $MSG_SIZE $ENV_FLAGS \
        --uri amqp://${RABBITMQ_USER}:${RABBITMQ_PASS}@${RABBITMQ_SERVICE}-server-0.${RABBITMQ_SERVICE}-nodes \
        --metrics-prometheus \
        --expected-instances ${ENV_COUNT} \
        --instance-sync-timeout 3600 \
        --metrics-command-line-arguments \
        --metrics-format compact \
        --use-millis \
        --confirm-timeout 300 \
        --servers-startup-timeout 300 \
        --producer-random-start-delay 1 \
        --time $TIME_PER_TEST \
        --id ${WORKLOAD_NAME} \
        -mt rabbitmq_cluster=${RABBITMQ_SERVICE},workload_name=${WORKLOAD_NAME},msg_size=${MSG_SIZE}

    # pause between test
    sleep 30
}

stream_perf_test() {
    WORKLOAD_NAME=${1}
    shift

    java  \
        -jar $STREAM_PERF_TEST_JAR $* -s $MSG_SIZE $ENV_FLAGS \
        --uris rabbitmq-stream://${RABBITMQ_USER}:${RABBITMQ_PASS}@${RABBITMQ_SERVICE} \
        --monitoring \
        --prometheus \
        --metrics-command-line-arguments \
        --metrics-tags rabbitmq_cluster=${RABBITMQ_SERVICE},workload_name=${WORKLOAD_NAME},msg_size=${MSG_SIZE} \
        --confirm-latency \
        --rpc-timeout 200 \
        --time ${TIME_PER_TEST}

    # pause between test
    sleep 30
}

emqtt_bench() {
    WORKLOAD_NAME=${1}
    shift

    sync $WORKLOAD_NAME

    /emqtt_bench/emqtt_bench $* -s $MSG_SIZE $ENV_FLAGS \
        --host ${RABBITMQ_SERVICE} \
        --username ${RABBITMQ_USER} \
        --password ${RABBITMQ_PASS} \
        --version 4

    # pause between test
    sleep 30
}
# call rabbitmqadmin against the test env
rabbitmq_admin() {
        rabbitmqadmin -H ${RABBITMQ_SERVICE} -u ${RABBITMQ_USER} -p ${RABBITMQ_PASS} $@
}

# wait for the env to be available
wait_for_cluster() {
    java -jar $AMQP_PERF_TEST_JAR -x 1 -y 0 -C 1 -c 1 \
        --id wait_for_cluster \
        --uri amqp://${RABBITMQ_USER}:${RABBITMQ_PASS}@${RABBITMQ_SERVICE} \
        --metrics-format compact \
        --use-millis \
        --confirm-timeout 300 \
        --servers-startup-timeout 600
}

# delete all queues in the given env
# by default queues are left intact, potentially with some messages
# WARNING: some tests need the queue(s) from previous tests (eg. when we publish and consume separately)
delete_all_queues() {
    for q in $(rabbitmq_admin --format bash list queues); do
        rabbitmq_admin delete queue name="${q}"
    done
}

wait_for_cluster

# let's go!
main

# stop for 12 hours; this is to have a clear idea of when the test finished
# hopefully the env is deleted within that time
sleep 43200
