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
    # one queue, as fast as you can
    perf_test one_fast -x 1 -y 1 -c 3000 -u "${PREFIX}-one_fast" -qa x-max-length=1000000 -ad false -f persistent
    delete_all_queues

    # publish at full speed, no consumers
    perf_test two_publishers_no_consumers -x 2 -y 0 -c 700 -u ${PREFIX}-publish_then_consume -qa x-max-length=5000000 -ad false -f persistent

    # consume without publishers present
    perf_test one_consumer_no_publishers -x 0 -y 1 -q 300 -u ${PREFIX}-publish_then_consume -qa x-max-length=5000000 -ad false -f persistent
    delete_all_queues

    # five high-throughput queues
    perf_test fivers -x 5 -y 5 -r 10000 -c 500 -qp ${PREFIX}-fivers-%d -qpf 1 -qpt 5 -qa x-max-length=1000000 -ad false -f persistent
    delete_all_queues

    # fanout from a publish to ten queues/consumers
    perf_test fanout10 -x 1 -y 10 -c 100 -e amq.fanout -t fanout -qp ${PREFIX}-q-%d -qpf 1 -qpt 10 -qa x-max-length=1000000 -ad false -f persistent
    delete_all_queues

    # one queue, confirm every message (synchronous publisher)
    perf_test one_one_one -x 1 -y 1 -c 1 -u ${PREFIX}-one_one_one -qa x-max-length=1000000 -ad false -f persistent
    delete_all_queues

    # seven thousands publishers, publishing to one queue; 7 consumers
    perf_test seven_thousand_slow_one_queue -x 7000 -y 7 -P 1 -c 1 -u ${PREFIX}-seven_thousand_slow_one_queue -qa x-max-length=1000000 -ad false -f persistent
    delete_all_queues

    # one thousand publishers, one thousand queues, one thousand consumers; low throughput
    perf_test thousand_slow_thousand_queues -x 1000 -y 1000 -P 0.1 -c 1 -qp ${PREFIX}-thousand_slow_thousand_queues-%d -qpf 1 -qpt 1000 -qa x-max-length=1000000 -ad false -f persistent
    delete_all_queues

    # build up a backlog of messages, then start competing consumers
    perf_test consumers_join_late -x 1 -c 100 -y 10 -q 300 -r 10000 -qa x-max-length=1000000 -u ${PREFIX}-consumers_join_late -ad false -f persistent -csd 150
    delete_all_queues

    # build up a backlog of messages, then start many consumers with a single active one (SAC)
    perf_test consumers_join_late_sac -x 1 -c 100 -q 300 -y 50 -r 10000 -qa x-max-length=1000000,x-single-active-consumer=true -u ${PREFIX}-consumers_join_late_sac -ad false -f persistent -csd 150
    delete_all_queues

    # just like one_fast but with multiack
    perf_test one_fast_multiack -x 1 -y 1 -c 3000 --multi-ack-every 1000 -u ${PREFIX}-one_fast_multiack -qa x-max-length=1000000 -ad false -f persistent
    delete_all_queues
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
