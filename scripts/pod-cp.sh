#!/usr/bin/env bash
# Copy files to/from the gateway container via kubectl cp.
#
# Usage:
#   scripts/pod-cp.sh <local-path> <remote-path>            # upload (default)
#   scripts/pod-cp.sh -d <remote-path> <local-path>         # download
#   scripts/pod-cp.sh [--kubeconfig <path>] [-n <ns>] [-v] (-d|-u) <a> <b>
#
# Note: the gateway container has a read-only root filesystem; copy to writable
# mounts only (/tmp, /home/node/.openclaw on the PVC).
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_kubectl

# Re-parse ARGS to split cp-specific flags from paths.
set -- "${ARGS[@]}"
NEW_ARGS=()
ACTION=upload

while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--download) ACTION=download; shift ;;
    -u|--upload)   ACTION=upload;   shift ;;
    -v|--verbose)  set -ex; NEW_ARGS+=("-v"); shift ;;
    *) NEW_ARGS+=("$1"); shift ;;
  esac
done

if [[ ${#NEW_ARGS[@]} -ne 2 ]]; then
  echo "Error: Exactly 2 path arguments required."
  echo "Usage: $0 [-d|-u] [--kubeconfig <path>] [-n <ns>] <arg1> <arg2>"
  exit 1
fi

pod=$(kubectl get pods --kubeconfig "${KUBE_CONFIG}" --namespace "${NAMESPACE}" \
  | grep "${DEPLOYMENT}" | grep "1/2" | awk -F' ' '{print $1}' | head -1)

if [[ -z "${pod}" ]]; then
  pod=$(kubectl get pods --kubeconfig "${KUBE_CONFIG}" --namespace "${NAMESPACE}" \
    | grep "${DEPLOYMENT}" | awk -F' ' '{print $1}' | head -1)
fi

[[ -n "${pod}" ]] || die "ERROR: Failed to find app pod!"

echo "Found ${pod}"

if [[ "${ACTION}" = "upload" ]]; then
  kubectl cp --kubeconfig "${KUBE_CONFIG}" -c "${CONTAINER}" "${NEW_ARGS[0]}" "${NAMESPACE}/${pod}:${NEW_ARGS[1]}"
else
  kubectl cp --kubeconfig "${KUBE_CONFIG}" -c "${CONTAINER}" "${NAMESPACE}/${pod}:${NEW_ARGS[0]}" "${NEW_ARGS[1]}" 2>&1 | grep -v "Removing leading"
fi
