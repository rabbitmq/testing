#!/opt/homebrew/bin/bash -x

export TIMEFORMAT=%R

KEXEC="kubectl -n my-namespace exec -c rabbitmq"
NODES=3

for khepri_db in "on" "off"; do
	for testgz in *.json.gz; do
		gunzip -k "$testgz"
		test=$(basename "$testgz" .gz)
		scenario="$test/$NODES/$khepri_db/$locator"
		mkdir -p scenarios/$scenario || true

		kubectl -n my-namespace apply -f "rabbitmq.yml" 
		sleep 5
		kubectl -n my-namespace rollout status --watch --timeout=600s statefulset/rmq-server
		echo "====== $NODES-node cluster deployed/started ======"
		kubectl -n my-namespace cp ./$testgz "rmq-server-0:/tmp"
		$KEXEC "rmq-server-0" -- gunzip "/tmp/$testgz"

		if [[ "$khepri_db" == "on" ]]; then
			$KEXEC "rmq-server-0" -- rabbitmqctl enable_feature_flag --opt-in khepri_db
		fi

		echo "$(date) IMPORT $scenario:"
		(time $KEXEC rmq-server-0 -- rabbitmqctl import_definitions "/tmp/$test") &>> "./scenarios/$scenario/import"

		sleep 10

		QUEUES=$(jq '.queues|length' $test)
		BINDINGS=$(jq '.bindings|length' $test)
		for i in $(seq 0 $((NODES-1)) ); do
			$KEXEC rmq-server-$i -- rabbitmqctl eval "$QUEUES = length(rabbit_amqqueue:list())."
			$KEXEC rmq-server-$i -- rabbitmqctl eval "$BINDINGS = length(rabbit_binding:list_explicit())."
		done

		sleep 10

		echo "$(date) REIMPORT $scenario:"
		(time $KEXEC rmq-server-0 -- rabbitmqctl import_definitions "/tmp/$test") &>> "./scenarios/$scenario/reimport"
		echo "$(date) STOP $scenario:"
		(time $KEXEC rmq-server-0 -- rabbitmqctl stop_app) &>> "./scenarios/$scenario/stop_app"
		echo "$(date) START $scenario:"
		(time $KEXEC rmq-server-0 -- rabbitmqctl start_app) &>> "./scenarios/$scenario/start_app"
		echo "$(date) ROLLING START $scenario:"
		kubectl -n my-namespace rollout restart statefulset rmq-server
		sleep 10
		time (kubectl -n my-namespace wait --timeout=7200s --for=condition=Ready=false pod rmq-server-0; sleep 10; kubectl wait --timeout=7200s --for=condition=Ready=true pod rmq-server-0) &>> "./scenarios/$scenario/rolling_start"

		echo "$(date) MIGRATE $scenario:"
		if [[ "$khepri_db" == "on" ]]; then
			echo 0 >> "./scenarios/$scenario/migrate"
		else
			# khepri was disabled, let's enable it now and measure the time to migrate
			(time $KEXEC rmq-server-0 -- rabbitmqctl enable_feature_flag --opt-in khepri_db) &>> "./scenarios/$scenario/migrate"
		fi

		# CLEANUP
		echo "$(date) CLEANUP"
		kubectl -n my-namespace delete --wait=true rabbitmqcluster rmq
		sleep 20
	done
done
