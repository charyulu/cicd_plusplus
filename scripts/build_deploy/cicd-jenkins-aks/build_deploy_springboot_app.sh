#!/bin/bash
# Synopsis: This script takes code from github, build and deploy through Jenkins to AKS
# References: 
#       https://docs.microsoft.com/en-us/azure/developer/jenkins/deploy-from-github-to-aks
#       https://github.com/Azure-Samples/azure-voting-app-redis
#       https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough?WT.mc_id=none-github-nepeters
#       https://docs.microsoft.com/en-us/azure/aks/tutorial-kubernetes-prepare-app?WT.mc_id=none-github-nepeters
#       Additional references: https://docs.microsoft.com/en-us/azure/developer/jenkins/plug-ins-for-azure
# User settings
timestamp=$(date +"%m%d%Y%H%M")
SUBSCRIPTION_NAME="gopal-pay-as-you-go"
RESOURCE_GROUP_NAME="cicd-jenk-rg-$timestamp"
ACR_NAME="cicdjenkacr$RANDOM"
AKS_CLUSTER="cicd-jenk-cluster"
AKS_NODE_COUNT=2
AKS_NODE_VM_SIZE="Standard_D4s_v3"
AKS_DNS_NAME_PREFIX="cicd-jenk-k8s"
AKS_NAMESPACE="default"
AZURE_REGION="westus"
PUBLIC_KEY="$(tr -d '\n' < ~/.ssh/id_rsa.pub)"
PROJ_BASE_DIR="/Users/sudarsanam/Documents/prasad/cicd_plusplus/scripts/build_deploy/cicd-jenkins-aks"
IMAGE_NAME="azure-vote-front"
POD_NAME="${IMAGE_NAME}"

# Prerequisites:
# Azure container registry (ACR) credential helper. (https://github.com/Azure/acr-docker-credential-helper)
# Azure CLI
# Java 8/ 11
# Maven, Git & docker

# Fork the project https://github.com/Azure-Samples/azure-voting-app-redis into personal github account
rm -rf azure-voting-app-redis
git clone git@github.com:charyulu/azure-voting-app-redis.git
cd azure-voting-app-redis
# Download, create and start Docker images of application Front end and backend
docker-compose up -d
# Login to Azure and capture ID of the required subscription account
SUBSCRIPTION_ID=$(az login | jq -r --arg SUBNAME "$SUBSCRIPTION_NAME" '.[] | select( .name == $SUBNAME) | .id')
az account set --subscription $SUBSCRIPTION_ID
# Create Resource group
echo "Creating resource group: $RESOURCE_GROUP_NAME"
az group create -n $RESOURCE_GROUP_NAME -l $AZURE_REGION
# Create private azure container registery
az acr create --resource-group $RESOURCE_GROUP_NAME --location $AZURE_REGION \
 --name ${ACR_NAME} --sku Basic
# set the default name for Azure Container Registry, otherwise you will need to specify the name in "az acr login"
# IMPORTANT NOTE: The credential created by "az acr login" is valid for 1 hour
#                 If encountered with 401 Unauthorized error anytime, run below commands again to reauthenticate.
az config set defaults.acr=${ACR_NAME}
az acr login
# Tag the image with the ACR login server name and a version number of v1
docker tag mcr.microsoft.com/azuredocs/azure-vote-front:v1 ${ACR_NAME}.azurecr.io/azure-vote-front:v1
# To cross check the success of above coomand, run: "docker images" - Image should be there with repository name prepended with ACR name
# Push the image to ACR
docker push ${ACR_NAME}.azurecr.io/azure-vote-front:v1
# Create AKS Cluster 
echo "Creating AKS cluster: ${AKS_CLUSTER} on resource group: $RESOURCE_GROUP_NAME"
node_resource_group=$(az aks create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $AKS_CLUSTER \
    --node-count $AKS_NODE_COUNT \
    --node-vm-size $AKS_NODE_VM_SIZE \
    --attach-acr $ACR_NAME \
    --dns-name-prefix $AKS_DNS_NAME_PREFIX --generate-ssh-keys | \
    jq -r '.nodeResourceGroup')
# Install Kubectl, if not available
STATUS=0
which -s kubectl;STATUS=$?
if [ $STATUS -eq 1 ];then
    echo -e "\n kubectl is unavailable. Installing..."
    az aks install-cli
fi
echo "The node resource group created by AKS is: $node_resource_group"
# Run below command to make connection to cluster from desktop and synch-up credentials.
echo "Downloading config and connecting to Cluster: ${AKS_CLUSTER} on resource group: $RESOURCE_GROUP_NAME"
az aks get-credentials -g $RESOURCE_GROUP_NAME -n $AKS_CLUSTER

# Update image URI in kubernetes deployment manifest with ACR created above
sed -i '' -e "s/mcr.microsoft.com\/azuredocs/${ACR_NAME}.azurecr.io/" ./azure-vote-all-in-one-redis.yaml
# Option - 1: Deploy application on AKS - In declarative mode - Using manifests
kubectl apply -f ./azure-vote-all-in-one-redis.yaml
kubectl get service azure-vote-front --watch

# Option -2: Deploy application on AKS -  In Imperfative mode - Using "kubectl run"
#kubectl run ${POD_NAME} --image=${ACR_NAME}.azurecr.io/${IMAGE_NAME}:latest
#Expose the application (container) externally
#kubectl expose pod ${POD_NAME} --type=LoadBalancer --port=80 --target-port=8080
# Get the External IP of the cluster:
echo "\n Waiting for POD to come up...";sleep 30
CLUSTER_PUBLIC_IP=$(kubectl get services -o=jsonpath='{.items[*].status.loadBalancer.ingress[0].ip}')
echo "\n Access application on: http://${CLUSTER_PUBLIC_IP}"

#TO CLEAN-UP - all resources created
#NODE_RG=$(az aks show --name $AKS_CLUSTER --resource-group $RESOURCE_GROUP_NAME | jq -r '.nodeResourceGroup')
#echo "Deleting resource group $NODE_RG"
#az group delete -n $RESOURCE_GROUP_NAME --no-wait -y
#echo "Deleting mode resource group $NODE_RG"
#az group delete -n $NODE_RG --no-wait -y
