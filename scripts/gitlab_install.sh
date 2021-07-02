#!/usr/bin/sh
# Synopsis: This script takes care of creating required AKS cluster and deploy Gitlab
mkdir -p /Users/sudarsanam/Documents/prasad/cicd_plusplus/workspace
cd /Users/sudarsanam/Documents/prasad/cicd_plusplus/workspace
git clone https://gitlab.com/gitlab-org/charts/gitlab.git
cd ./gitlab
#CREATE - all required AKS resources created
    ./scripts/aks_bootstrap_script.sh --resource-group gs-rg \
    --cluster-name aks-gitlab-cluster \
    --region westus --node-count 2 \
    --node-vm-size Standard_D4s_v3 \
    --public-ip-name gitlab-ext-ip \
    --create-resource-group \
    --create-public-ip up

# To connect to cluster
./scripts/aks_bootstrap_script.sh --resource-group gs-rg --cluster-name aks-gitlab-cluster -f ~/.kube/config creds

#TO DELETE - all AKS resources created
./scripts/aks_bootstrap_script.sh --resource-group gs-rg \
--cluster-name aks-gitlab-cluster \
--delete-resource-group down

# Deploy Gitlab
# NOTE: Get Public IP address from Ext IP resource created as part of cluster creation.
helm repo add gitlab https://charts.gitlab.io/
helm repo update
helm upgrade --install gitlab gitlab/gitlab \
  --timeout 600s \
  --set global.hosts.domain=example.com \
  --set global.hosts.externalIP=104.209.40.146 \
  --set certmanager-issuer.email=me@example.com

# Output of helm install command
#Release "gitlab" does not exist. Installing it now.
#NAME: gitlab
#LAST DEPLOYED: Thu Jul  1 21:29:24 2021
#NAMESPACE: default
#STATUS: deployed
#REVISION: 1
#NOTES:
#NOTICE: The minimum required version of PostgreSQL is now 12. See https://gitlab.com/gitlab-org/charts/gitlab/-/blob/master/doc/installation/upgrade.md for more details.

#NOTICE: You've installed GitLab Runner without the ability to use 'docker in docker'.
#The GitLab Runner chart (gitlab/gitlab-runner) is deployed without the `privileged` flag by default for security purposes. This can be changed by setting `gitlab-runner.runners.privileged` to `true`. Before doing so, please read the GitLab Runner chart's documentation on why we
#chose not to enable this by default. See https://docs.gitlab.com/runner/install/kubernetes.html#running-docker-in-docker-containers-with-gitlab-runners

#Help us improve the installation experience, let us know how we did with a 1 minute survey:
#https://gitlab.fra1.qualtrics.com/jfe/form/SV_6kVqZANThUQ1bZb?installation=helm&release=14-0

kubectl get secret gitlab-gitlab-initial-root-password -ojsonpath='{.data.password}' | base64 --decode ; echo

# Uninstall Gitlab
helm uninstall gitlab
