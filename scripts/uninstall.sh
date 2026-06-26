#!/usr/bin/env bash
# Remove OpenClaw workloads from the cluster, preserving the PVC (data kept)
# and the namespace. The Secret/openclaw-secrets is also removed.
#
# To wipe everything including data: `kubectl --kubeconfig <cfg> delete namespace <ns>`
#
# Usage: scripts/uninstall.sh [--kubeconfig <path>] [-n <ns>] [-v]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_kubectl

echo "Deleting OpenClaw resources in namespace ${NAMESPACE} (PVC retained)..."
kubectl --kubeconfig "${KUBE_CONFIG}" -n "${NAMESPACE}" delete \
  deployment "${DEPLOYMENT}" \
  service "${DEPLOYMENT}" \
  configmap "${CONFIGMAP}" \
  ingress "${DEPLOYMENT}" \
  secret openclaw-secrets \
  --ignore-not-found "${ARGS[@]}"

echo
echo "Kept PVC freechat-openclaw and namespace ${NAMESPACE} (data preserved)."
echo "To remove everything: kubectl --kubeconfig ${KUBE_CONFIG} delete namespace ${NAMESPACE}"
