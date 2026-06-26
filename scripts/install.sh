#!/usr/bin/env bash
# Deploy OpenClaw via the official Kustomize manifests + private overlay.
#
# Steps:
#   1. Build Secret/openclaw-secrets from secrets.env (envFrom source).
#   2. Ensure the namespace exists (idempotent).
#   3. Ensure the data PVC `freechat-openclaw` exists (create from
#      configs/k8s/overlay/pvc.yaml only if missing -- preserves existing data).
#   4. Apply the Kustomize overlay (kubectl apply -k).
#   5. Best-effort: patch the bound PV reclaimPolicy -> Retain (legacy `retain: true`).
#   6. Restart the deployment and wait for rollout.
#
# Usage: scripts/install.sh [--kubeconfig <path>] [--secrets <path>] [-n <ns>] [-v]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_kubectl

[[ -f "${KUBE_CONFIG}" ]] || die "ERROR: kubeconfig not found: ${KUBE_CONFIG}
  Place it at configs/k8s/kube-private.conf or pass --kubeconfig <path>."
[[ -f "${SECRETS_ENV}" ]] || die "ERROR: secrets.env not found: ${SECRETS_ENV}
  Create it (KEY=value per line). It is gitignored; see configs/k8s/deploy.env."

# 1) Secret/openclaw-secrets from secrets.env (client-side dry-run -> server-side apply).
echo "Applying Secret/openclaw-secrets from ${SECRETS_ENV}..."
kubectl --kubeconfig "${KUBE_CONFIG}" create secret generic openclaw-secrets \
  --from-env-file="${SECRETS_ENV}" \
  --namespace="${NAMESPACE}" \
  --dry-run=client -o yaml \
  | kubectl --kubeconfig "${KUBE_CONFIG}" apply --server-side --field-manager=openclaw -f - "${ARGS[@]}"

# 2) Namespace (idempotent).
echo "Ensuring namespace ${NAMESPACE}..."
kubectl --kubeconfig "${KUBE_CONFIG}" create namespace "${NAMESPACE}" \
  --dry-run=client -o yaml \
  | kubectl --kubeconfig "${KUBE_CONFIG}" apply -f - >/dev/null

# 3) Ensure the data PVC exists. The Deployment mounts `freechat-openclaw`;
#    create it only if missing so an existing (migrated) data PVC is preserved.
PVC_MANIFEST="${PROJECT_PATH}/configs/k8s/overlay/pvc.yaml"
if kubectl --kubeconfig "${KUBE_CONFIG}" -n "${NAMESPACE}" get pvc freechat-openclaw &>/dev/null; then
  echo "PVC freechat-openclaw already exists (preserving existing data)."
else
  echo "PVC freechat-openclaw not found; creating from ${PVC_MANIFEST}..."
  kubectl --kubeconfig "${KUBE_CONFIG}" apply -f "${PVC_MANIFEST}" -n "${NAMESPACE}"
fi

# 4) Apply the overlay (temp wrapper adds the images: transformer from deploy.env).
OVERLAY_DIR="$(prepare_overlay)"
trap 'rm -rf "${OVERLAY_DIR}"' EXIT
echo "Applying kustomize overlay (image ${OPENCLAW_IMAGE})..."
kubectl --kubeconfig "${KUBE_CONFIG}" apply -k "${OVERLAY_DIR}" -n "${NAMESPACE}" "${ARGS[@]}"

# 5) Best-effort PV reclaim policy -> Retain (needs cluster-admin; non-fatal).
PV=$(kubectl --kubeconfig "${KUBE_CONFIG}" -n "${NAMESPACE}" get pvc freechat-openclaw \
     -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
if [[ -n "${PV}" ]]; then
  kubectl --kubeconfig "${KUBE_CONFIG}" patch pv "${PV}" \
    -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}' 2>/dev/null \
    && echo "PV ${PV} reclaimPolicy -> Retain" \
    || echo "WARN: could not patch PV ${PV} reclaimPolicy (needs cluster-admin)."
fi

# 6) Rollout.
echo "Restarting deployment/${DEPLOYMENT}..."
kubectl --kubeconfig "${KUBE_CONFIG}" -n "${NAMESPACE}" rollout restart "deployment/${DEPLOYMENT}" 2>/dev/null || true
kubectl --kubeconfig "${KUBE_CONFIG}" -n "${NAMESPACE}" rollout status "deployment/${DEPLOYMENT}" --timeout=300s

echo
echo "Done. Gateway Control UI:"
echo "  kubectl --kubeconfig ${KUBE_CONFIG} -n ${NAMESPACE} port-forward svc/${DEPLOYMENT} 18789:18789"
echo "  open http://localhost:18789"
echo "Voice webhook: https://${INGRESS_HOST}/voice/webhook"
