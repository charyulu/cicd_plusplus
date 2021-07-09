#!/bin/bash
# Synopsis: This script takes care of build, create docker image and deploy to AKS
# References: 
#       https://docs.microsoft.com/en-us/azure/developer/java/spring-framework/deploy-spring-boot-java-app-on-kubernetes
#       https://github.com/GoogleContainerTools/jib
#       https://github.com/GoogleContainerTools/jib/tree/master/jib-maven-plugin  
# User settings
timestamp=$(date +"%m%d%Y%H%M")
SUBSCRIPTION_NAME="gopal-pay-as-you-go"
RESOURCE_GROUP_NAME="bld-deploy-rg-$timestamp"
ACR_NAME="blddeployacr$RANDOM"
AKS_CLUSTER="bld-deploy-cluster"
AKS_NODE_COUNT=2
AKS_NODE_VM_SIZE="Standard_D4s_v3"
AKS_DNS_NAME_PREFIX="bld-deploy-k8s"
AKS_NAMESPACE="default"
AZURE_REGION="westus"
PUBLIC_KEY="$(tr -d '\n' < ~/.ssh/id_rsa.pub)"
PROJ_BASE_DIR="/Users/sudarsanam/Documents/prasad/cicd_plusplus/scripts/build_deploy/sample-springboot"
IMAGE_NAME="spring-boot-docker"
POD_NAME="${IMAGE_NAME}"


# Prerequisites:
# Azure container registry (ACR) credential helper. (https://github.com/Azure/acr-docker-credential-helper)
# Azure CLI
# Java 8/ 11
# Maven, Git & docker
rm -rf gs-spring-boot-docker
git clone https://github.com/spring-guides/gs-spring-boot-docker.git
cd gs-spring-boot-docker
cd complete
# Run traditional maven build and deploy to ensure code is intact
#mvn package spring-boot:run
#curl http://localhost:8080

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
# Replace pom.xml with the template content and update the registry name with the name of ACR created above 
cp -f "${PROJ_BASE_DIR}/pom-template.xml" ./pom.xml
# Referece: Special treatment for sed on Mac. Refer: https://stackoverflow.com/questions/19456518/invalid-command-code-despite-escaping-periods-using-sed
sed -i '' -e "s/<docker.image.prefix>.*$/<docker.image.prefix>${ACR_NAME}.azurecr.io<\/docker.image.prefix>/g" ./pom.xml
# build the image and push it to the registry (ACR)
az acr login && mvn compile jib:build
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
# Deploy application in AKS
kubectl run ${POD_NAME} --image=${ACR_NAME}.azurecr.io/${IMAGE_NAME}:latest

#Expose the application (container) externally
kubectl expose pod ${POD_NAME} --type=LoadBalancer --port=80 --target-port=8080
# Get the External IP of the cluster:
echo "\n Waiting for POD to come up...";sleep 30
CLUSTER_PUBLIC_IP=$(kubectl get services -o=jsonpath='{.items[*].status.loadBalancer.ingress[0].ip}')
echo "\n Access application on: http://${CLUSTER_PUBLIC_IP}"
curl "${CLUSTER_PUBLIC_IP}"

#TO CLEAN-UP - all resources created
#NODE_RG=$(az aks show --name $AKS_CLUSTER --resource-group $RESOURCE_GROUP_NAME | jq -r '.nodeResourceGroup')
#echo "Deleting resource group $NODE_RG"
#az group delete -n $RESOURCE_GROUP_NAME --no-wait -y
#echo "Deleting mode resource group $NODE_RG"
#az group delete -n $NODE_RG --no-wait -y
