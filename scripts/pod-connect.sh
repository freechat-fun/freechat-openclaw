#!/usr/bin/env bash

source $(dirname ${BASH_SOURCE[0]})/setenv.sh

nohup bash ${PROJECT_PATH}/scripts/pod-forward.sh &>/tmp/openclaw-forward.log &
