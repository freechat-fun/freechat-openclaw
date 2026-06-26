#!/usr/bin/env bash
# Launch pod-forward.sh in the background (nohup), logging to /tmp/pod-forward.log.
#
# Usage: scripts/pod-connect.sh [--kubeconfig <path>] [-n <ns>] [-v]
source "$(dirname "${BASH_SOURCE[0]}")/setenv.sh"

nohup bash "${PROJECT_PATH}/scripts/pod-forward.sh" &>/tmp/pod-forward.log &
echo "Port-forward started in background. Logs: /tmp/pod-forward.log"
echo "Stop with: pkill -f pod-forward.sh"
