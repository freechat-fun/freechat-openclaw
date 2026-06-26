#!/usr/bin/env bash
# Open an interactive shell in the gateway container.
# Prefers a pod that is mid-deploy (1/2), otherwise any matching pod.
#
# Usage: scripts/pod-shell.sh [--kubeconfig <path>] [-n <ns>] [-v]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_kubectl

pod=$(kubectl get pods --kubeconfig "${KUBE_CONFIG}" --namespace "${NAMESPACE}" \
  | grep "${DEPLOYMENT}" | grep "1/2" | awk -F' ' '{print $1}' | head -1)

if [[ -z "${pod}" ]]; then
  pod=$(kubectl get pods --kubeconfig "${KUBE_CONFIG}" --namespace "${NAMESPACE}" \
    | grep "${DEPLOYMENT}" | awk -F' ' '{print $1}' | head -1)
fi

[[ -n "${pod}" ]] || die "ERROR: Failed to find app pod!"

echo "Found ${pod}"
kubectl exec --kubeconfig "${KUBE_CONFIG}" --namespace "${NAMESPACE}" \
  -it "${pod}" -c "${CONTAINER}" -- /bin/bash
