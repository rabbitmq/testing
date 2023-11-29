#!/usr/bin/env bash

if [[ -z "$(which ytt)" ]]; then
    echo "Please install ytt (https://github.com/carvel-dev/ytt)"
    exit 1
fi

mkdir -p rabbitmq
mkdir -p client

SCENARIO_FILE=${1:-scenario.yaml}
shift
SCRIPT_FILES=${*:-script.sh}

if [[ ! -f ${SCENARIO_FILE} ]]; then
    echo "scenario file doesn't exist"
    echo "create scenario.yaml or pass an argument, eg. \`./generate.sh scenario-versions.yaml\`"
    exit 1
fi

ytt -f .schema.yaml -f templates/rabbitmq.yaml -f "$SCENARIO_FILE" > "rabbitmq/scenario.yaml"

for script in $SCRIPT_FILES; do
    SCRIPT_NAME="$(basename $script .sh)"
    ytt --allow-symlink-destination .. -f .schema.yaml --data-value-file script="$script" --data-value script_name="$SCRIPT_NAME" -f templates/client.yaml -f "$SCENARIO_FILE" > "client/$SCRIPT_NAME.yaml"
done

cat <<HELP

Generated files are in rabbitmq/ and client/

Use the following commands to deploy them:

    kubectl apply -f rabbitmq/
    kubectl apply -f client/

if you modified script.sh, delete the old instances first:

    kubectl delete -f client/
HELP
