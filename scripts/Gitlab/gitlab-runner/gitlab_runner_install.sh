#!/bin/bash
# Synopsis: This script takes care of creating required AKS cluster and deploy Gitlab runner
timestamp=$(date +"%m%d%Y%H%M")
SUBSCRIPTION_NAME="gopal-pay-as-you-go"
RESOURCE_GROUP_NAME="gl-runner-rg-$timestamp"
AKS_CLUSTER="gl-runner-cluster"
AKS_NODE_COUNT=2
AKS_NODE_VM_SIZE="Standard_D4s_v3"
AKS_NAMESPACE="default"
AZURE_REGION="westus"
PUBLIC_KEY="$(tr -d '\n' < ~/.ssh/id_rsa.pub)"
# Create Resource group
echo "Creating resource group: $RESOURCE_GROUP_NAME"
az group create -n $RESOURCE_GROUP_NAME -l $AZURE_REGION
# Create AKS Cluster 
echo "Creating AKS cluster: ${AKS_CLUSTER} on resource group: $RESOURCE_GROUP_NAME"
node_resource_group=$(az aks create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $AKS_CLUSTER \
    --node-count $AKS_NODE_COUNT \
    --node-vm-size $AKS_NODE_VM_SIZE \
    --generate-ssh-keys | \
    jq -r '.nodeResourceGroup')

echo "The node resource group created by AKS is: $node_resource_group"
# Run below command to make connection to cluster from desktop and synch-up credentials.
echo "Connecting to Cluster: ${AKS_CLUSTER} on resource group: $RESOURCE_GROUP_NAME"
az aks get-credentials -g $RESOURCE_GROUP_NAME -n $AKS_CLUSTER
# Deploy Gitlab runner
helm repo add gitlab https://charts.gitlab.io
helm repo update
helm upgrade --install gitlab-runner gitlab/gitlab-runner --namespace $AKS_NAMESPACE -f ./gitlab-runner-values.yaml 

# Uninstall Gitlab runner
#helm uninstall gitlab-runner
#helm delete --namespace $AKS_NAMESPACE gitlab-runner

#TO CLEAN-UP - all AKS resources created
#az group delete -n $RESOURCE_GROUP_NAME --no-wait -y
#NODE_RG=$(az aks show --name $AKS_CLUSTER --resource-group $RESOURCE_GROUP_NAME | jq -r '.nodeResourceGroup')
#echo "Deleting cluster resource group $NODE_RG"
#az group delete -n $NODE_RG --no-wait -y
