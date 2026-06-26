#!/usr/bin/env bash
# Remove cert-manager and the ClusterIssuer.
#
# Usage: scripts/uninstall-cm.sh [--kubeconfig <path>] [-v]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_kubectl
check_helm

# Delete the ClusterIssuer first (scope: cluster).
# NOTE: legacy used `kubectl clusterissuer -l ...` (missing `delete` subcommand) -- corrected.
kubectl --kubeconfig "${KUBE_CONFIG}" delete clusterissuer "${CLUSTER_ISSUER}" --ignore-not-found 2>/dev/null || true

helm uninstall --kubeconfig "${KUBE_CONFIG}" --namespace "${CERT_MANAGER_NAMESPACE}" \
  "${ARGS[@]}" cert-manager
