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
export SUBSCRIPTION_NAME="gopal-pay-as-you-go"
export RESOURCE_GROUP_NAME="cicd-jenk-rg-$timestamp"
export ACR_NAME="cicdjenkacr$RANDOM"
export AKS_CLUSTER="cicd-jenk-cluster"
export AKS_NODE_COUNT=2
export AKS_NODE_VM_SIZE="Standard_D4s_v3"
export AKS_DNS_NAME_PREFIX="cicd-jenk-k8s"
export AKS_NAMESPACE="default"
export AZURE_REGION="westus"
export PUBLIC_KEY="$(tr -d '\n' < ~/.ssh/id_rsa.pub)"
export PROJ_BASE_DIR="/Users/sudarsanam/Documents/prasad/cicd_plusplus/scripts/build_deploy/cicd-jenkins-aks"
export IMAGE_NAME="azure-vote-front"
export POD_NAME="${IMAGE_NAME}"
export JENKINS_VM_NAME="cicd-jenk-vm"
export JENKINS_VM_ADMIN_USER="charyulu"
# Give absolute path to .kube/config
export KUBE_CONFIG_FILE="/Users/sudarsanam/.kube/config"

# Prerequisites:
# Azure container registry (ACR) credential helper. (https://github.com/Azure/acr-docker-credential-helper)
# Azure CLI
# Java 8/ 11
# Maven, Git & docker

# Function: Install and deploy Jenkins on VM
# Reference: https://github.com/Azure-Samples/azure-voting-app-redis/tree/master/jenkins-tutorial

function install_jenkins() {
    if [ -f $KUBE_CONFIG_FILE ]; then
        # Create a resource group.
        az group create --name $RESOURCE_GROUP_NAME --location $AZURE_REGION

        # Create a new virtual machine, this creates SSH keys if not present.
        az vm create --resource-group $RESOURCE_GROUP_NAME --name $JENKINS_VM_NAME --admin-username $JENKINS_VM_ADMIN_USER --image UbuntuLTS --generate-ssh-keys

        # Open port 80 to allow web traffic to host.
        az vm open-port --port 80 --resource-group $RESOURCE_GROUP_NAME --name $JENKINS_VM_NAME  --priority 101

        # Open port 22 to allow ssh traffic to host.
        az vm open-port --port 22 --resource-group $RESOURCE_GROUP_NAME --name $JENKINS_VM_NAME --priority 102

        # Open port 8080 to allow web traffic to host.
        az vm open-port --port 8080 --resource-group $RESOURCE_GROUP_NAME --name $JENKINS_VM_NAME --priority 103

        # Use CustomScript extension to install NGINX.
        # Reference: https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-linux
        az vm extension set --publisher Microsoft.Azure.Extensions --version 2.0 --name CustomScript --vm-name $JENKINS_VM_NAME --resource-group $RESOURCE_GROUP_NAME --settings '{"fileUris": ["https://raw.githubusercontent.com/charyulu/cicd_plusplus/main/scripts/build_deploy/cicd-jenkins-aks/config-jenkins.sh"],"commandToExecute": "./config-jenkins.sh"}'

        # Get public IP
        JENKINS_VM_PUBLIC_IP=$(az vm list-ip-addresses --resource-group $RESOURCE_GROUP_NAME --name $JENKINS_VM_NAME --query [0].virtualMachine.network.publicIpAddresses[0].ipAddress -o tsv)
        echo "\n JENKINS_VM_PUBLIC_IP = $JENKINS_VM_PUBLIC_IP"
        # Copy Kube config file to Jenkins
        ssh -o "StrictHostKeyChecking no" $JENKINS_VM_ADMIN_USER@$JENKINS_VM_PUBLIC_IP sudo chmod 777 /var/lib/jenkins
        yes | scp $KUBE_CONFIG_FILE $JENKINS_VM_ADMIN_USER@$JENKINS_VM_PUBLIC_IP:/var/lib/jenkins/config
        ssh -o "StrictHostKeyChecking no" $JENKINS_VM_ADMIN_USER@$JENKINS_VM_PUBLIC_IP sudo chmod 777 /var/lib/jenkins/config

        # Get Jenkins Unlock Key
        JENKINS_URL="http://$JENKINS_VM_PUBLIC_IP:8080"
        echo "Open Jenkins in browser at: $JENKINS_URL"
        echo "Enter the following to Unlock Jenkins:"
        ssh -o "StrictHostKeyChecking no" $JENKINS_VM_ADMIN_USER@$JENKINS_VM_PUBLIC_IP sudo "cat /var/lib/jenkins/secrets/initialAdminPassword"
        echo "\n\n Take above said steps and press any key to continue...";read
    else
        echo "Kubernetes configuration / authentication file not found. Run az aks get-credentials to download this file."
    fi
}
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
# Create VM, install and configure Jenkins
install_jenkins

#TO CLEAN-UP - all resources created
#NODE_RG=$(az aks show --name $AKS_CLUSTER --resource-group $RESOURCE_GROUP_NAME | jq -r '.nodeResourceGroup')
#echo "Deleting resource group $NODE_RG"
#az group delete -n $RESOURCE_GROUP_NAME --no-wait -y
#echo "Deleting mode resource group $NODE_RG"
#az group delete -n $NODE_RG --no-wait -y
