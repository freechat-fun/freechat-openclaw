#!/usr/bin/env bash
# Restart the OpenClaw deployment (e.g. to pick up runtime changes on the PVC
# without re-applying manifests).
#
# Usage: scripts/restart.sh [--kubeconfig <path>] [-n <ns>] [-v]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_kubectl

kubectl rollout restart --kubeconfig "${KUBE_CONFIG}" --namespace "${NAMESPACE}" \
  "${ARGS[@]}" \
  deployment "${DEPLOYMENT}"
