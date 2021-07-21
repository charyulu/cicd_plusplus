#!/bin/bash

#********************* WARNING: UNTESTED CODE. #*********************
# Synopsis: This script installs Cloud Foundry on Kubernetes (cf-for-k8s)
# References: 
#       https://cf-for-k8s.io/
#       https://cf-for-k8s.io/docs/      
#  
# Setup Params. 
# Get Docker hub credentials  
read -rp "Enter Docker Hub Username: " DOCKER_HUB_USER
read -rsp "Enter Docker Hub Password: " DOCKER_HUB_PASS

# ===================== Install Supporting tools ========================
#Install Kind. 
#   Reference: https://kind.sigs.k8s.io/docs/user/quick-start/#installation
brew install kind

#Install ytt & kapp. 
#   Reference: https://carvel.dev/
brew tap vmware-tanzu/carvel
brew install ytt kbld kapp imgpkg kwt vendir

#Install BOSH CLI. 
#   Reference: https://bosh.io/docs/cli-v2-install/#install
#               https://bosh.io/docs/cli-v2-install/#additional-dependencies
brew install cloudfoundry/tap/bosh-cli
xcode-select --install
brew install openssl

# Install Cloud foundry CLI 
# Reference: https://docs.cloudfoundry.org/cf-cli/install-go-cli.html
brew install cloudfoundry/tap/cf-cli@7

# Install cf-for-k8s 
cd /Users/sudarsanam/Documents/prasad/cicd_plusplus/scripts/PCF/cf-for-k8s
git clone https://github.com/cloudfoundry/cf-for-k8s.git -b main
cd cf-for-k8s
TMP_DIR=/Users/sudarsanam/Documents/prasad/tmp; mkdir -p ${TMP_DIR}

# Create local kubernetes cluster
# Reference: https://kind.sigs.k8s.io/docs/user/quick-start/
kind create cluster --config=./deploy/kind/cluster.yml --image kindest/node:v1.20.2

# Create cf values file. This is the file that configures your deployment
./hack/generate-values.sh -d vcap.me > ${TMP_DIR}/cf-values.yml

cat << EOF >> ${TMP_DIR}/cf-values.yml
app_registry:
  hostname: https://index.docker.io/
  repository_prefix: "${DOCKER_HUB_USER}"
  username: "${DOCKER_HUB_USER}"
  password: "${DOCKER_HUB_PASS}"

add_metrics_server_components: true
enable_automount_service_account_token: true
load_balancer:
  enable: false
metrics_server_prefer_internal_kubelet_address: true
remove_resource_requirements: true
use_first_party_jwt_tokens: true
EOF

# deploy cf-for-k8s
kapp deploy -a cf -f <(ytt -f config -f ${TMP_DIR}/cf-values.yml)
