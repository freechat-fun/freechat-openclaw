#!/usr/bin/env bash
# Remove ingress-nginx from the cluster.
#
# Usage: scripts/uninstall-in.sh [--kubeconfig <path>] [-v]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_helm

helm uninstall --kubeconfig "${KUBE_CONFIG}" --namespace ingress-default \
  "${ARGS[@]}" ingress-nginx
