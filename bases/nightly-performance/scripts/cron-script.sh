#!/bin/bash
set -euxo pipefail

apt-get update && apt-get install -y jq gettext-base

SIM_NAME=${JOB_NAMESPACE}-$(date +%Y-%m-%d-%H)
export SIM_NAME
if [ -z $NETWORK_NAME ]; then
  echo "NETWORK_NAME is not set. Exiting."
  exit 1
else
  kubectl get networks.keramik.3box.io $NETWORK_NAME
  if [ $? -ne 0 ]; then
    echo "Network $NETWORK_NAME does not exist. Exiting."
    exit 1
  fi
fi
NETWORK_NAMESPACE=keramik-${NETWORK_NAME}
export NETWORK_NAMESPACE

# Check for existing simulations
EXISTING_SIMUlATIONS=$(kubectl get simulations.keramik.3box.io  -n $NETWORK_NAMESPACE --no-headers=true|wc -l)
if [ $EXISTING_SIMUlATIONS -gt 0 ]; then
  echo "There are existing simulations. Exiting."
  exit 1
fi

curl -L https://github.com/mikefarah/yq/releases/download/v4.40.7/yq_linux_amd64 -o yq
chmod +x yq

echo "Waiting for the network to stabilize and bootstrap"
kubectl wait --for=condition=complete job/bootstrap -n "${NETWORK_NAMESPACE}"
# Deploy or update podmonitors
kubectl apply -n "${NETWORK_NAMESPACE}" -f /config/podmonitors.yaml

# Start the simulation and tag resources
if [ -f /simulation/simulation.yaml ]; then
  ./yq -e '.metadata.name = env(SIM_NAME), .metadata.namespace = env(NETWORK_NAMESPACE)' \
  /simulation/simulation.yaml > simulation.yaml
else
  ./yq -e '.metadata.name = env(SIM_NAME), .metadata.namespace = env(NETWORK_NAMESPACE)' \
    /config/simulation.yaml > simulation.yaml
fi

# Start simulation
kubectl apply -f simulation.yaml
SIMULATION_RUNTIME=$(./yq e '.spec.runTime' simulation.yaml)
export SIMULATION_RUNTIME
SIMULATION_SCENARIO=$(./yq e '.spec.scenario' simulation.yaml)
export SIMULATION_SCENARIO
sleep 60 # wait for the simulation to start
KERAMIK_SIMULATE_NAME=$(kubectl get job simulate-manager \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="manager")].env[?(@.name=="SIMULATE_NAME")].value}' -n "${NETWORK_NAMESPACE}")
export KERAMIK_SIMULATE_NAME
if [ -n "$KERAMIK_SIMULATE_NAME" ]; then
  kubectl label pods --overwrite -l app=ceramic scenario="$SIMULATION_SCENARIO" simulation="$KERAMIK_SIMULATE_NAME" -n "${NETWORK_NAMESPACE}"
  kubectl label pods --overwrite -l app=otel scenario="$SIMULATION_SCENARIO" simulation="$KERAMIK_SIMULATE_NAME" -n "${NETWORK_NAMESPACE}"
fi

echo "Simulation will run for $SIMULATION_RUNTIME minutes"
sleep $((SIMULATION_RUNTIME * 60))

# why is this not working?
# Maybe loop and watch for conditions
sleep 300 # wait for the simulation to finish
kubectl  get job simulate-manager -n "${NETWORK_NAMESPACE}" -o jsonpath='{.status}'

SUCCEEDED=$(kubectl  get job simulate-manager -n "${NETWORK_NAMESPACE}" -o jsonpath='{.status.succeeded}')
FAILED=$(kubectl  get job simulate-manager -n "${NETWORK_NAMESPACE}" -o jsonpath='{.status.failed}')
if [[ "$SUCCEEDED" -gt 0 ]]; then
  SIMULATION_STATUS_TAG="succeeded"
  SIMULATION_COLOR=5763719
elif [[ "$FAILED" -gt 0 ]]; then
  SIMULATION_STATUS_TAG="failed"
  SIMULATION_COLOR=15548997
else
  SIMULATION_STATUS_TAG="unknown"
  SIMULATION_COLOR=10070709
fi

export SIMULATION_STATUS_TAG
export SIMULATION_COLOR
export DISCORD_WEBHOOK_URL

# Send Discord notification
envsubst < /notifications/notification-template.json  > message.json
cat message.json
curl -v -H "Content-Type: application/json" -X POST -d @./message.json "$DISCORD_WEBHOOK_URL_SUCCEEDED"

if [[ "$FAILED" -gt 0 ]]; then
  curl -v -H "Content-Type: application/json" -X POST -d @./message.json "$DISCORD_WEBHOOK_URL_FAILED"
fi

# Delete simulation
kubectl delete -f simulation.yaml
