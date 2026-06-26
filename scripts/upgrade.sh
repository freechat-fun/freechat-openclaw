#!/usr/bin/env bash
# Re-apply the OpenClaw Kustomize overlay after editing manifests, openclaw.json,
# or secrets.env. Rebuilds the Secret, re-applies the overlay, and restarts
# the deployment. (Equivalent to install.sh minus namespace create + PV patch.)
#
# Usage: scripts/upgrade.sh [--kubeconfig <path>] [--secrets <path>] [-n <ns>] [-v]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_kubectl

[[ -f "${KUBE_CONFIG}" ]] || die "ERROR: kubeconfig not found: ${KUBE_CONFIG}"
[[ -f "${SECRETS_ENV}" ]] || die "ERROR: secrets.env not found: ${SECRETS_ENV}"

echo "Re-applying Secret/openclaw-secrets from ${SECRETS_ENV}..."
kubectl --kubeconfig "${KUBE_CONFIG}" create secret generic openclaw-secrets \
  --from-env-file="${SECRETS_ENV}" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml \
  | kubectl --kubeconfig "${KUBE_CONFIG}" apply --server-side --field-manager=openclaw -f - "${ARGS[@]}"

OVERLAY_DIR="$(prepare_overlay)"
trap 'rm -rf "${OVERLAY_DIR}"' EXIT
echo "Re-applying kustomize overlay (image ${OPENCLAW_IMAGE})..."
kubectl --kubeconfig "${KUBE_CONFIG}" apply -k "${OVERLAY_DIR}" -n "${NAMESPACE}" "${ARGS[@]}"

echo "Restarting deployment/${DEPLOYMENT}..."
kubectl --kubeconfig "${KUBE_CONFIG}" -n "${NAMESPACE}" rollout restart "deployment/${DEPLOYMENT}" 2>/dev/null || true
kubectl --kubeconfig "${KUBE_CONFIG}" -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}" --timeout=300s

echo "Done."
