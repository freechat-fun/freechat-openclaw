#!/usr/bin/env bash
# Tail logs of the gateway container. Prefers a pod that is mid-deploy (1/2),
# otherwise any matching pod.
#
# Usage: scripts/pod-logs.sh [--kubeconfig <path>] [-n <ns>] [-v] [kubectl args, e.g. -f]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_kubectl

# Prefer a deploying pod (1/2 ready with 2 containers), else any matching pod.
pod=$(kubectl get pods --kubeconfig "${KUBE_CONFIG}" --namespace "${NAMESPACE}" \
  | grep "${DEPLOYMENT}" | grep "1/2" | awk -F' ' '{print $1}' | head -1)

if [[ -z "${pod}" ]]; then
  pod=$(kubectl get pods --kubeconfig "${KUBE_CONFIG}" --namespace "${NAMESPACE}" \
    | grep "${DEPLOYMENT}" | awk -F' ' '{print $1}' | head -1)
fi

[[ -n "${pod}" ]] || die "ERROR: Failed to find app pod!"

echo "Found ${pod}"
kubectl logs --kubeconfig "${KUBE_CONFIG}" --namespace "${NAMESPACE}" \
  "${ARGS[@]}" -c "${CONTAINER}" "${pod}"
