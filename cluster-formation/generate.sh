#!/bin/bash

if [[ -z "$(which ytt)" ]]; then
    echo "Please install ytt (https://github.com/carvel-dev/ytt)"
    exit 1
fi

mkdir -p rabbitmq

SCENARIO_FILE=${1:-scenario.yaml}
shift
SCRIPT_FILES=${*:-script.sh}

if [[ ! -f ${SCENARIO_FILE} ]]; then
    echo "scenario file doesn't exist"
    echo "create scenario.yaml or pass an argument, eg. \`./generate.sh scenario-versions.yaml\`"
    exit 1
fi

ytt -f .schema.yaml -f templates/rabbitmq.yaml -f "$SCENARIO_FILE" > "rabbitmq/scenario.yaml"

cat <<HELP

Generated files are in rabbitmq/ and client/

Use the following commands to deploy them:

    kubectl apply -f rabbitmq/
HELP
