#!/usr/bin/env bash

source $(dirname ${BASH_SOURCE[0]})/setenv.sh

check_helm

# helm repo add openclaw https://serhanekicii.github.io/openclaw-helm
# helm repo update
helm template --kubeconfig ${KUBE_CONFIG} --namespace ${NAMESPACE} --create-namespace -f ${values_yaml} \
  ${ARGS[*]} \
  ${PROJECT_NAME} \
  openclaw/openclaw \
  --version ${HELM_version}
