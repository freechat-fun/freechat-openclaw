#!/usr/bin/env bash
# Sync the vendored Kustomize base (configs/k8s/base) from the official
# OpenClaw manifests, then re-apply the local customization.
#
# This is the one-command way to inherit upstream Kubernetes improvements
# (new probes, securityContext tightening, new resources like NetworkPolicy/
# PDB, etc.) without re-deriving them from a deprecated Helm wrapper.
#
# Source: the sibling `openclaw` repo by default (../openclaw). Override with
# --source <path-to-openclaw>/scripts/k8s/manifests if your checkout is elsewhere
# (e.g. clone https://github.com/openclaw/openclaw and point --source at its
# scripts/k8s/manifests).
#
# What it does:
#   1. Copy every *.yaml from the upstream manifests dir into configs/k8s/base
#      (cleaning stale files first so upstream removals/renames don't linger).
#   2. Re-apply the local customization on base/kustomization.yaml: drop the
#      `- pvc.yaml` resource line (we reuse the existing data PVC
#      `freechat-openclaw`, managed standalone by scripts/install.sh). Any NEW
#      resources upstream adds to kustomization.yaml are preserved.
#   3. Run scripts/render.sh to validate. If an upstream rename breaks an
#      overlay patch (container/volume/port name a patch targets), this fails
#      loudly -- edit configs/k8s/overlay/*-patch.yaml to match.
#
# After syncing, review `git diff configs/k8s/base` and commit.
set -euo pipefail

PROJECT_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BASE_DIR="${PROJECT_PATH}/configs/k8s/base"
SOURCE="${PROJECT_PATH}/../openclaw/scripts/k8s/manifests"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,26p' "${BASH_SOURCE[0]}"
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -d "${SOURCE}" ]]; then
  echo "ERROR: upstream manifests dir not found: ${SOURCE}" >&2
  echo "Clone https://github.com/openclaw/openclaw as a sibling," >&2
  echo "or pass --source <path-to-openclaw>/scripts/k8s/manifests" >&2
  exit 1
fi

echo "Syncing base"
echo "  from: ${SOURCE}"
echo "  into: ${BASE_DIR}"
echo

# 1) Clean stale base YAMLs, then copy upstream manifests verbatim.
rm -f "${BASE_DIR}/"*.yaml
cp -p "${SOURCE}/"*.yaml "${BASE_DIR}/"
echo "Copied $(ls "${BASE_DIR}/"*.yaml | wc -l) manifest files."

# 2) Re-apply the local customization on kustomization.yaml: drop our previous
#    header (if present) and the pvc.yaml resource line, then re-prepend the
#    header. New upstream resources in kustomization.yaml are preserved.
KUSTOMIZATION="${BASE_DIR}/kustomization.yaml"
python3 - "${KUSTOMIZATION}" <<'PY'
import sys, re
p = sys.argv[1]
src = open(p).read()
# Strip a leading comment block only if it is OUR header (contains the marker).
m = re.match(r'^(#[^\n]*\n)+', src)
if m and 'LOCAL CUSTOMIZATION' in m.group(0):
    src = src[m.end():]
# Remove the pvc.yaml resource line (we manage the data PVC standalone).
src = re.sub(r'(?m)^[ \t]*-[ \t]*pvc\.yaml[ \t]*\n', '', src)
header = (
    "# Vendored from openclaw/scripts/k8s/manifests/kustomization.yaml.\n"
    "# LOCAL CUSTOMIZATION: pvc.yaml is intentionally excluded. The freechat-openclaw\n"
    "# deployment reuses the existing data PVC `freechat-openclaw` (claimName set in\n"
    "# the overlay's deployment-patch.yaml) and manages that PVC outside Kustomize\n"
    "# (scripts/install.sh applies configs/k8s/overlay/pvc.yaml only if the PVC is\n"
    "# missing). Excluding pvc.yaml here prevents Kustomize from creating/adopting\n"
    "# the base's openclaw-home-pvc, which would be an empty orphan PVC.\n"
)
open(p, 'w').write(header + src)
PY
echo "Re-applied local customization (excluded pvc.yaml from kustomization.yaml)."
echo

# 3) Validate: render the overlay. A patch that targets a renamed upstream
#    field will fail here.
echo "Validating via render.sh..."
if bash "${PROJECT_PATH}/scripts/render.sh" >/dev/null 2>/tmp/sync-render.err; then
  echo "render.sh OK."
else
  echo "WARN: render.sh failed after sync -- an overlay patch may need updating:" >&2
  sed 's/^/  /' /tmp/sync-render.err >&2
  rm -f /tmp/sync-render.err
  echo "Edit configs/k8s/overlay/*-patch.yaml to match the new upstream field names." >&2
  exit 2
fi
rm -f /tmp/sync-render.err

echo
echo "Done. Review and commit:"
echo "  git diff --stat configs/k8s/base"
echo "If a patch broke, edit configs/k8s/overlay/*-patch.yaml to match new field names."
