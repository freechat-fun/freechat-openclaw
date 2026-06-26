#!/usr/bin/env bash
# Continuously port-forward the gateway (18789) to localhost, reconnecting
# if the pod restarts. Stopped with Ctrl-C. Launch in the background via
# pod-connect.sh.
#
# Usage: scripts/pod-forward.sh [--kubeconfig <path>] [-n <ns>] [-v]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_kubectl

stop() { exit 0; }
trap stop SIGINT

while true; do
  pod=$(kubectl get pods --kubeconfig "${KUBE_CONFIG}" --namespace "${NAMESPACE}" \
    | grep "${DEPLOYMENT}" | awk -F' ' '{print $1}' | head -1)

  [[ -n "${pod}" ]] || die "ERROR: Failed to find app pod!"

  echo "Found ${pod}"
  kubectl port-forward --kubeconfig "${KUBE_CONFIG}" --namespace "${NAMESPACE}" \
    pod/"${pod}" 18789:18789
done
