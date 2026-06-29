#!/usr/bin/env bash
# Shared environment for freechat-openclaw deployment scripts.
#
# Sources configs/k8s/deploy.env for non-secret parameters, then applies
# CLI flag overrides. Exposes the variables consumed by the other scripts:
#   NAMESPACE, KUBE_CONFIG, KUSTOMIZE_DIR, SECRETS_ENV,
#   DEPLOYMENT, CONTAINER, INGRESS_*, CERT_MANAGER_*, LETSENCRYPT_EMAIL, CLUSTER_ISSUER
#
# Flags (accepted by every script that sources this file):
#   --kubeconfig <path>   Override kubeconfig (default: configs/k8s/kube-private.conf)
#   --secrets <path>      Override secrets.env path
#   -n|--namespace <ns>   Override namespace
#   -p|--project <name>   Override Deployment name / pod grep target (default: openclaw)
#   -v|--verbose          set -ex
# Any other args are collected into ARGS[] and passed through to kubectl/helm.

PROJECT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG_DIR="${PROJECT_PATH}/configs/k8s"

# Paths (deploy.env may override with repo-relative values; normalized below)
DEPLOY_ENV="${CONFIG_DIR}/deploy.env"
SECRETS_ENV="${CONFIG_DIR}/secrets.env"
KUSTOMIZE_DIR="${CONFIG_DIR}/overlay"
KUBE_CONFIG="${CONFIG_DIR}/kube-private.conf"

# Defaults (used if deploy.env is absent).
# NOTE: DEPLOYMENT and CONFIGMAP are the post-namePrefix resource names
# (overlay kustomization.yaml uses namePrefix: freechat-, so base `openclaw`
# -> `freechat-openclaw` and `openclaw-config` -> `freechat-openclaw-config`).
# If you change namePrefix, update these (or override via -p / deploy.env).
DEPLOYMENT="freechat-openclaw"
CONFIGMAP="freechat-openclaw-config"
CONTAINER="gateway"
OPENCLAW_NAMESPACE="fun-freechat"
INGRESS_CLASS="nginx"
INGRESS_HOST="openclaw.jiangsier.xyz"
TLS_SECRET="openclaw.jiangsier.xyz-tls"
CLUSTER_ISSUER="freechat-letsencrypt-http01"
CERT_MANAGER_NAMESPACE="cert-manager"
CERT_MANAGER_VERSION="v1.16.1"
LETSENCRYPT_EMAIL=""

# Source non-secret params (exports via `set -a`).
if [[ -f "${DEPLOY_ENV}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${DEPLOY_ENV}"
  set +a
fi

NAMESPACE="${OPENCLAW_NAMESPACE}"

# Normalize repo-relative paths to absolute.
[[ "${KUBE_CONFIG}"   != /* ]] && KUBE_CONFIG="${PROJECT_PATH}/${KUBE_CONFIG}"
[[ "${KUSTOMIZE_DIR}" != /* ]] && KUSTOMIZE_DIR="${PROJECT_PATH}/${KUSTOMIZE_DIR}"
[[ "${SECRETS_ENV}"   != /* ]] && SECRETS_ENV="${PROJECT_PATH}/${SECRETS_ENV}"

# Container images (repo:tag) from deploy.env. Defaults match the tags in
# configs/k8s/overlay/deployment-patch.yaml; the scripts override them at
# apply/render time via the kustomize `images:` transformer (see prepare_overlay).
OPENCLAW_IMAGE="${OPENCLAW_IMAGE:-ghcr.io/openclaw/openclaw:2026.6.9}"
CHROMIUM_IMAGE="${CHROMIUM_IMAGE:-chromedp/headless-shell:148.0.7778.97}"
OPENCLAW_REPO="${OPENCLAW_IMAGE%:*}"
OPENCLAW_TAG="${OPENCLAW_IMAGE##*:}"
CHROMIUM_REPO="${CHROMIUM_IMAGE%:*}"
CHROMIUM_TAG="${CHROMIUM_IMAGE##*:}"

# OpenClaw runtime config is decoupled from the k8s ConfigMap: the real config
# is plain JSON at OPENCLAW_JSON (gitignored, alongside the other sensitive files
# in configs/k8s/). The TRACKED configs/k8s/overlay/openclaw-config-cm.yaml is a
# non-sensitive ConfigMap patch placeholder (`data.openclaw.json: "{}"`) -- visible
# to git. merge_openclaw_config (below) writes the real config into a TEMP patch
# that prepare_overlay's wrapper injects ON TOP of that placeholder, so the tracked
# file is never dirtied with real config at runtime (kustomize applies the overlay's
# patches first, then the wrapper's, so the real config wins).
OPENCLAW_JSON="${CONFIG_DIR}/openclaw.json"

# merge_openclaw_config <out>: render a temp ConfigMap strategic-merge patch at
# <out> whose data.openclaw.json is the real config from OPENCLAW_JSON (as a `|-`
# block scalar, 4-space content indent -- matches the hand-edited format).
# prepare_overlay injects this temp patch via the wrapper kustomization so it
# overrides the tracked placeholder's `openclaw.json: "{}"`. Called from
# prepare_overlay so install/upgrade/render (and sync-base via render) all stay
# in sync. Dies loudly if openclaw.json is missing.
merge_openclaw_config() {
  local out="$1"
  [[ -f "${OPENCLAW_JSON}" ]] || die "ERROR: openclaw.json missing: ${OPENCLAW_JSON}
  Put your real runtime config (plain JSON; \${ENV} substitution ok) there. It is gitignored."
  python3 - "${OPENCLAW_JSON}" "${out}" <<'PY'
import sys
src, out = sys.argv[1:3]
text = open(src).read().rstrip("\n")
body = "\n".join("    " + l if l.strip() else l for l in text.split("\n"))
open(out, "w").write(
    "apiVersion: v1\n"
    "kind: ConfigMap\n"
    "metadata:\n"
    "  name: openclaw-config\n"
    "  labels:\n"
    "    app: openclaw\n"
    "data:\n"
    "  openclaw.json: |-\n"
    + body + "\n"
)
PY
}

# prepare_overlay: emit a temp kustomization.yaml that references the real
# overlay dir (so its relative ../base and patch paths still resolve) and adds
# an `images:` transformer with the tags from deploy.env. Prints the temp dir
# path on stdout. The caller MUST `rm -rf` it (typically via `trap ... EXIT`).
# This keeps version bumps in deploy.env without editing tracked manifests.
prepare_overlay() {
  local tmp rel
  tmp="$(mktemp -d)"
  # Render the real openclaw.json into a temp ConfigMap patch in the temp dir.
  # The wrapper kustomization below injects it on top of the tracked placeholder
  # patch (overlay/openclaw-config-cm.yaml, `openclaw.json: "{}"`): kustomize
  # builds the overlay's patches first, then the wrapper's, so the real config
  # overrides the placeholder. The tracked file is never written at runtime.
  merge_openclaw_config "${tmp}/openclaw-config-cm.yaml"
  # kustomize forbids absolute paths in resources: -- use a relative path from
  # the temp kustomization to the real overlay dir. The overlay's own ../base
  # and patch paths still resolve correctly (kustomize resolves them relative
  # to the overlay, not the wrapper).
  rel="$(realpath --relative-to="${tmp}" "${KUSTOMIZE_DIR}")"
  cat > "${tmp}/kustomization.yaml" <<EOF
# Auto-generated by scripts/setenv.sh (prepare_overlay). Do not edit.
# Wraps the real overlay (brings its tracked patches, incl. the
# openclaw-config-cm.yaml PLACEHOLDER) + a real openclaw.json patch that
# OVERRIDES the placeholder's data.openclaw.json + an images: transformer
# whose tags come from configs/k8s/deploy.env (OPENCLAW_IMAGE / CHROMIUM_IMAGE).
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ${rel}
patches:
  - path: openclaw-config-cm.yaml
images:
  - name: ghcr.io/openclaw/openclaw
    newName: ${OPENCLAW_REPO}
    newTag: "${OPENCLAW_TAG}"
  - name: chromedp/headless-shell
    newName: ${CHROMIUM_REPO}
    newTag: "${CHROMIUM_TAG}"
EOF
  printf '%s\n' "${tmp}"
}

ARGS=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --kubeconfig) KUBE_CONFIG="$2"; shift 2 ;;
    --secrets)    SECRETS_ENV="$2"; shift 2 ;;
    -n|--namespace) NAMESPACE="$2"; shift 2 ;;
    -p|--project)   DEPLOYMENT="$2"; shift 2 ;;
    -v|--verbose)   set -ex ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

die() { echo "$*" >&2; echo >&2; exit 1; }

check_kubectl() { command -v kubectl &>/dev/null || die "ERROR: kubectl not found in PATH."; }
check_helm()    { command -v helm    &>/dev/null || die "ERROR: helm not found in PATH."; }
check_docker()  { command -v docker  &>/dev/null || die "ERROR: docker not found in PATH."; }
