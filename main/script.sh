#!/bin/bash

trap "exit" SIGINT SIGTERM

AMQP_PERF_TEST_JAR=${PERF_TEST_JAR:-"/perf_test/perf-test.jar"}
STREAM_PERF_TEST_JAR=${PERF_TEST_JAR:-"/stream_perf_test/stream-perf-test.jar"}
RABBITMQ_SERVICE=${RABBITMQ_SERVICE:-localhost}
RABBITMQ_USER=${RABBITMQ_USER:-guest}
RABBITMQ_PASS=${RABBITMQ_PASS:-guest}
QUEUE_TYPE=${QUEUE_TYPE:-"classic"}
MSG_SIZE=${MSG_SIZE:-12}

TIME_PER_TEST=300

# the test(s) to run
main() {
    ##
    ## AMQP 0.9.1
    ##
   
    # one queue, as fast as you can
    perf_test one_fast -x 1 -y 1 -c 3000 -u one_fast -qa x-max-length=5000000
    delete_all_queues

    # publish at full speed, no consumers
    perf_test two_publishers_no_consumers -x 2 -y 0 -c 700 -u publish_then_consume -qa x-max-length=5000000

    # consume without publishers present
    perf_test one_consumer_no_publishers -x 0 -y 1 -q 300 -u publish_then_consume -qa x-max-length=5000000
    delete_all_queues

    # five high-throughput queues
    perf_test fivers -x 5 -y 5 -r 10000 -c 500 -qp fivers-%d -qpf 1 -qpt 5 -qa x-max-length=1000000
    delete_all_queues

    # fanout from a publish to ten queues/consumers
    perf_test fanout10 -x 1 -y 10 -c 100 -e amq.fanout -t fanout -qp q-%d -qpf 1 -qpt 10 -qa x-max-length=1000000
    delete_all_queues

    # one queue, confirm every message (synchronous publisher)
    perf_test one_one_one -x 1 -y 1 -c 1 -u one_one_one -qa x-max-length=1000000
    delete_all_queues

    # seven thousands publishers, publishing to one queue; 7 consumers
    perf_test seven_thousand_slow_one_queue -x 7000 -y 7 -P 1 -c 1 -u seven_thousand_slow_one_queue -qa x-max-length=1000000
    delete_all_queues

    # one thousand publishers, one thousand queues, one thousand consumers; low throughput
    perf_test thousand_slow_thousand_queues -x 1000 -y 1000 -P 0.1 -c 1 -qp thousand_slow_thousand_queues-%d -qpf 1 -qpt 1000 -qa x-max-length=1000000
    delete_all_queues

    # build up a backlog of messages, then start competing consumers
    perf_test consumers_join_late -x 1 -c 100 -y 10 -q 300 -r 10000 -qa x-max-length=1000000 -u consumers_join_late  -csd 150
    delete_all_queues

    # build up a backlog of messages, then start many consumers with a single active one (SAC)
    perf_test consumers_join_late_sac -x 1 -c 100 -q 300 -y 50 -r 10000 -qa x-max-length=1000000,x-single-active-consumer=true -u consumers_join_late_sac  -csd 150
    delete_all_queues

    # just like one_fast but with multiack
    perf_test one_fast_multiack -x 1 -y 1 -c 3000 --multi-ack-every 1000 -u one_fast_multiack -qa x-max-length=1000000
    delete_all_queues

    # publish expiring messages and dead letter them
    rabbitmqadmin declare policy --name ttl_dlq --pattern publish_only_ttl --definition '{"dead-letter-exchange":"","dead-letter-routing-key":"ttl_dlq"}' --apply-to queues
    perf_test declare_ttl_dlq -u ttl_dlq  -C 1 -c 1
    perf_test publish_only_ttl -x 1 -y 0 -c 1 -u publish_only_ttl --message-properties expiration=10000
    rabbitmqadmin delete policy --name ttl_dlq
    delete_all_queues

    # initially as above but without TTL, then NACK em all
    rabbitmqadmin declare policy --name nack_dlq --pattern publish_then_nack --definition '{"dead-letter-exchange":"","dead-letter-routing-key":"nack_dlq"}' --apply-to queues
    perf_test declare_nack_dlq -u nack_dlq  -C 1 -c 1
    perf_test publish_to_nack -x 1 -y 0 -c 1 -u publish_then_nack -qa x-max-length=250000
    perf_test nack_published -x 0 -y 4 -u publish_then_nack -qa x-max-length=250000  --nack --requeue false
    rabbitmqadmin delete policy --name nack_dlq
    delete_all_queues

    ##
    ## AMQP 1.0
    ##

    omq_amqp amqp10_consumers_join_late -x 50 -c 10 -r 1000 -y 10 --publish-to '/queues/amqp10_consumers_join_late' --consume-from '/queues/amqp10_consumers_join_late' --consumer-credits 1000 --cleanup-queues --consumer-startup-delay 150s

    omq_amqp amqp10_one_fast -x 1 -y 1 -c 200 --publish-to '/queues/amqp10_one_fast' --consume-from '/queues/amqp10_one_fast' --consumer-credits 1000 --cleanup-queues

    omq_amqp amqp10_publish_only -x 2 -y 0 -c 200 --publish-to '/queues/amqp10_publish_then_consume' --consume-from '/queues/amqp10_publish_then_consume'

    omq_amqp amqp10_consume_only -x 0 -y 1 --publish-to '/queues/amqp10_publish_then_consume' --consume-from '/queues/amqp10_publish_then_consume' --consumer-credits 1000 --cleanup-queues

    omq_amqp amqp10_fivers -x 5 -y 5 -r 10000 -c 100 -t '/queues/amqp10_fivers-%d' -T '/queues/amqp10_fivers-%d' --consumer-credits 1000 --cleanup-queues

    omq_amqp amqp10_one_one_one -x 1 -y 1 -c 1  -t '/queues/amqp10_one_one_one' -T '/queues/amqp10_one_one_one' --cleanup-queues

}

##
## HELPERS (hopefully no need to change anything there)
##

queue_type_perf_test_flag() {
    case $1 in
        "classic")
            echo "-ad false -f persistent"
            ;;
        "quorum")
            echo "--quorum-queue"
            ;;
        "stream")
            echo "--stream-queue"
            ;;
        *)
            echo "Unknown queue type: $1"
            exit 1
            ;;
    esac
}


omq_amqp() {
    WORKLOAD_NAME=${1}
    shift
    # TODO $ENV_FLAGS
    /omq amqp $* -s $MSG_SIZE \
        --uri amqp://${RABBITMQ_USER}:${RABBITMQ_PASS}@${RABBITMQ_SERVICE}/ \
        --time ${TIME_PER_TEST}s \
        --metric-tags rabbitmq_cluster=${RABBITMQ_SERVICE},workload_name=${WORKLOAD_NAME},msg_size=${MSG_SIZE} \
        --expected-instances ${ENV_COUNT} \
        --queues $QUEUE_TYPE \
        --expected-instances-endpoint omq-sync
    # pause between test
    sleep 30
}

# run perf-test with the provided flags and all the necessary boilerplate
# note - by default we connect to server-0 for consistency between envs and tests
# this is bad for some tests; remove `-server-0.${RABBITMQ_SERVICE}-nodes` if you don't want that
perf_test() {
    QUEUE_TYPE_FLAG=$(queue_type_perf_test_flag $QUEUE_TYPE)
    WORKLOAD_NAME=${1}
    shift

    # connect to server-0 for consistency between environments and test runs (connection-queue locality)
    # expose Prometheus metrics with additional tags for filtering in the dashboard
    # producer random startup delay to avoid batches of messages being sent at the same time
    java -jar $AMQP_PERF_TEST_JAR $* -s $MSG_SIZE $QUEUE_TYPE_FLAG $ENV_FLAGS \
        --uri amqp://${RABBITMQ_USER}:${RABBITMQ_PASS}@${RABBITMQ_SERVICE}-server-0.${RABBITMQ_SERVICE}-nodes \
        --metrics-prometheus \
        --expected-instances ${ENV_COUNT} \
        --instance-sync-timeout 3600 \
        --metrics-command-line-arguments \
        --metrics-format compact \
        --use-millis \
        --confirm-timeout -1 \
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
# call rabbitmqadmin against the test env
rabbitmqadmin() {
        rabbitmqadmin-ng --non-interactive --base-uri http://${RABBITMQ_SERVICE} -u ${RABBITMQ_USER} -p ${RABBITMQ_PASS} $@
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
    for q in $(rabbitmqadmin list queues | awk '{print $1}' | grep -v '^$'); do
        rabbitmqadmin delete queue --name "${q}"
    done
}

wait_for_cluster

# let's go!
main

# stop for 12 hours; this is to have a clear idea of when the test finished
# hopefully the env is deleted within that time
sleep 43200
