#!/usr/bin/sh
# Synopsis: This script takes care of creating required AKS cluster and deploy Gitlab
mkdir -p /Users/sudarsanam/Documents/prasad/cicd_plusplus/workspace
cd /Users/sudarsanam/Documents/prasad/cicd_plusplus/workspace
git clone https://gitlab.com/gitlab-org/charts/gitlab.git
cd ./gitlab
#CREATE - all required AKS resources created
# Simple command:
./scripts/aks_bootstrap_script.sh --create-resource-group up
#./scripts/aks_bootstrap_script.sh --resource-group gs-rg \
#    --cluster-name aks-gitlab-cluster \
#    --region westus --node-count 2 \
#    --node-vm-size Standard_D4s_v3 \
#    --public-ip-name gitlab-ext-ip \
#    --create-resource-group \
#    --create-public-ip up

# Check the # of resources on a clean slate environment
az resource list | jq '. | length'  # Should be 7 items

# To connect to cluster
./scripts/aks_bootstrap_script.sh -f ~/.kube/config creds
#./scripts/aks_bootstrap_script.sh --resource-group gs-rg --cluster-name aks-gitlab-cluster -f ~/.kube/config creds

# Deploy Gitlab
# NOTE: Get Public IP address from Ext IP resource created as part of cluster creation.
helm repo add gitlab https://charts.gitlab.io/
helm repo update
helm install gitlab gitlab/gitlab \
  --set global.hosts.domain=charyulu.bng \
  --set certmanager-issuer.email=me@example.com

#helm upgrade --install gitlab gitlab/gitlab \
#  --timeout 600s \
#  --set global.hosts.domain=charyulu.com \
#  --set global.hosts.externalIP=20.81.120.227 \
#  --set certmanager-issuer.email=me@charyulu.com \
#  --set gitlab-runner.runners.privilegd=true \
#  --set certmanager.rbac.create=false \
#  --set nginx-ingress.rbac.createRole=false \
#  --set prometheus.rbac.create=false \
#  --set gitlab-runner.rbac.create=false

# Retrieve IP addresses
kubectl get ingress -lrelease=gitlab

# Create DNS Entries to Public IP source

# Collect the password to sign in as 'root'
kubectl get secret gitlab-gitlab-initial-root-password -ojsonpath='{.data.password}' | base64 --decode ; echo

# Uninstall Gitlab
helm uninstall gitlab

#TO CLEAN-UP - all AKS resources created
./scripts/aks_bootstrap_script.sh --delete-resource-group down
#./scripts/aks_bootstrap_script.sh --resource-group gs-rg \
#--cluster-name aks-gitlab-cluster \
#--delete-resource-group down

# To delete Resource Groups:
az group list | jq '.[].name'
az group delete -n <Resource group Name> -y --no-wait
az group list | jq '.[] | [.name, .properties.provisioningState]'
