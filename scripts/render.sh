#!/usr/bin/env bash
# Render the final Kubernetes manifests (overlay + base, with the image tags
# from deploy.env applied via the images: transformer) to stdout without
# applying. Useful for inspecting what would be deployed.
#
# Usage: scripts/render.sh [-v]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

check_kubectl

OVERLAY_DIR="$(prepare_overlay)"
trap 'rm -rf "${OVERLAY_DIR}"' EXIT
kubectl kustomize "${OVERLAY_DIR}" "${ARGS[@]}"
