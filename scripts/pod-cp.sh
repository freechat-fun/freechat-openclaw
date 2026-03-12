#!/usr/bin/env bash

source $(dirname ${BASH_SOURCE[0]})/setenv.sh

set -- "${ARGS[@]}"
NEW_ARGS=()
ACTION=upload

while [ $# -gt 0 ]
do
  case $1 in
    -d|--download)
      ACTION=download
      shift
      ;;
    -u|--upload)
      ACTION=upload
      shift
      ;;
    -v|--verbose)
      set -eux
      NEW_ARGS+=("-v")
      shift
      ;;
    *)
      NEW_ARGS+=("$1")
      shift
      ;;
  esac
done

if [ ${#NEW_ARGS[@]} -ne 2 ]; then
    echo "Error: Exactly 2 arguments required, but got $#"
    echo "Usage: $0 <arg1> <arg2>"
    exit 1
fi

# find deploying one
pod=$(kubectl get pods --kubeconfig ${KUBE_CONFIG} --namespace ${NAMESPACE} \
  | grep "${PROJECT_NAME}" | grep "1/2" | awk -F' ' '{print $1}' | head -1)

if [[ -z "${pod}" ]]; then
  # find anyone
  pod=$(kubectl get pods --kubeconfig ${KUBE_CONFIG} --namespace ${NAMESPACE} \
    | grep "${PROJECT_NAME}" | awk -F' ' '{print $1}' | head -1)
fi

test -n "${pod}" || die "ERROR: Failed to find app pod!"

echo "Found ${pod}"

if [[ "${ACTION}" = "upload" ]]; then
  kubectl cp --kubeconfig ${KUBE_CONFIG} -c main "${NEW_ARGS[0]}" ${NAMESPACE}/${pod}:"${NEW_ARGS[1]}"
else
  kubectl cp --kubeconfig ${KUBE_CONFIG} -c main "${NAMESPACE}/${pod}:${NEW_ARGS[0]}" "${NEW_ARGS[1]}" 2>&1 | grep -v "Removing leading"
fi