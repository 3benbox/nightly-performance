#!/bin/bash
set -euxo pipefail

apt-get update && apt-get install -y jq gettext-base
curl -L https://github.com/mikefarah/yq/releases/download/v4.40.7/yq_linux_amd64 -o yq
chmod +x yq

NETWORK_NAMESPACE=${JOB_NAMESPACE} # From deployment env introspection
export NETWORK_NAMESPACE
WAIT_MINUTES=10

# Start loop
i=0
while true; do
  echo "########## Loop iteration $i started ##########"
  # Check for existing simulations
  EXISTING_SIMUlATION=$(kubectl get simulations.keramik.3box.io --no-headers=true -o name -n "$NETWORK_NAMESPACE")
  if [[ -n "$EXISTING_SIMUlATION" ]]; then
    echo "Deleting existing simulation ${EXISTING_SIMUlATION}."
    kubectl delete "$EXISTING_SIMUlATION" -n "$NETWORK_NAMESPACE"
  fi

  SIMULATION_RUNTIME=$(./yq e '.spec.runTime' /simulations/recon-event-sync.yaml)
  export SIMULATION_RUNTIME

  # Create the simulation job
  kubectl apply -f /simulations/recon-event-sync.yaml
  echo "Simulation will run for $SIMULATION_RUNTIME minutes"
  sleep $((SIMULATION_RUNTIME * 60))

  sleep 120 # wait for the simulation to finish
  kubectl  get job simulate-manager -n "${NETWORK_NAMESPACE}" -o jsonpath='{.status}'

  # Delete the simulation job
  kubectl delete -f /simulations/recon-event-sync.yaml

  # Sleep for WAIT_MINUTES
  sleep $((WAIT_MINUTES * 60))

  # Run ceramic-new-streams simulation
  SIMULATION_RUNTIME=$(./yq e '.spec.runTime' /simulations/ceramic-new-streams.yaml)
  export SIMULATION_RUNTIME

  # Create the simulation job
  kubectl apply -f /simulations/ceramic-new-streams.yaml
  echo "Simulation will run for $SIMULATION_RUNTIME minutes"
  sleep $((SIMULATION_RUNTIME * 60))

  sleep 120 # wait for the simulation to finish
  kubectl  get job simulate-manager -n "${NETWORK_NAMESPACE}" -o jsonpath='{.status}'

  # Delete the simulation job
  kubectl delete -f /simulations/ceramic-new-streams.yaml

  # Sleep for WAIT_MINUTES
  sleep $((WAIT_MINUTES * 60))
  date
  echo "########## Loop iteration $i completed ##########"
  i=$((i + 1))
done