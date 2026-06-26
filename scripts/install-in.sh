#!/usr/bin/env bash
# Deploy ingress-nginx into the cluster (prerequisite for the public /voice
# ingress). Installs into namespace `ingress-default` with
# externalTrafficPolicy=Local so client IPs are preserved for trustedProxies.
#
# Usage: scripts/install-in.sh [--kubeconfig <path>] [-v]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_helm

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx &>/dev/null
helm repo update

helm upgrade --kubeconfig "${KUBE_CONFIG}" --install --create-namespace \
  --namespace ingress-default \
  --set controller.service.externalTrafficPolicy=Local \
  "${ARGS[@]}" \
  ingress-nginx ingress-nginx/ingress-nginx
