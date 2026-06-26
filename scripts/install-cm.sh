#!/usr/bin/env bash
# Deploy cert-manager + a Let's Encrypt HTTP01 ClusterIssuer (prerequisite for
# the TLS certificate on the public ingress).
#
# ClusterIssuer name = ${CLUSTER_ISSUER} (default: freechat-letsencrypt-http01),
# which MUST match the cert-manager.io/cluster-issuer annotation in
# configs/k8s/overlay/ingress.yaml. (The legacy chart mismatched this name.)
#
# Requires LETSENCRYPT_EMAIL in configs/k8s/deploy.env.
#
# Usage: scripts/install-cm.sh [--kubeconfig <path>] [-v]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_kubectl
check_helm

[[ -n "${LETSENCRYPT_EMAIL}" ]] || die "ERROR: LETSENCRYPT_EMAIL is empty.
  Set it in configs/k8s/deploy.env before running install-cm.sh."

helm repo add jetstack https://charts.jetstack.io &>/dev/null
helm repo update

helm upgrade --kubeconfig "${KUBE_CONFIG}" --install cert-manager jetstack/cert-manager \
  --create-namespace \
  --namespace "${CERT_MANAGER_NAMESPACE}" \
  --version "${CERT_MANAGER_VERSION}" \
  --set installCRDs=true \
  "${ARGS[@]}"

# Wait for the cert-manager webhook before applying the ClusterIssuer
# (avoids "no matches for kind ClusterIssuer" race on fresh installs).
echo "Waiting for cert-manager webhook..."
kubectl --kubeconfig "${KUBE_CONFIG}" -n "${CERT_MANAGER_NAMESPACE}" wait \
  deployment/cert-manager-webhook --for=condition=Available --timeout=120s 2>/dev/null \
  || echo "WARN: cert-manager webhook wait timed out; applying ClusterIssuer anyway."

CLUSTER_ISSUER_YAML="$(mktemp -d)/clusterissuer.yaml"
trap 'rm -rf "$(dirname "${CLUSTER_ISSUER_YAML}")"' EXIT
cat > "${CLUSTER_ISSUER_YAML}" <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: ${CLUSTER_ISSUER}
  labels:
    app.kubernetes.io/name: openclaw
spec:
  acme:
    email: ${LETSENCRYPT_EMAIL}
    privateKeySecretRef:
      name: ${CLUSTER_ISSUER}-key
    server: https://acme-v02.api.letsencrypt.org/directory
    solvers:
      - http01:
          ingress:
            class: ${INGRESS_CLASS}
EOF

# NOTE: legacy used `kubectl -f` (missing subcommand) -- corrected to `apply -f`.
kubectl --kubeconfig "${KUBE_CONFIG}" apply -f "${CLUSTER_ISSUER_YAML}"
echo "ClusterIssuer ${CLUSTER_ISSUER} applied (email: ${LETSENCRYPT_EMAIL}, ingress class: ${INGRESS_CLASS})."
