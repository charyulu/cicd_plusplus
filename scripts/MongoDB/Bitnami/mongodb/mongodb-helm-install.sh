#!/bin/bash
#Reference: https://docs.gitlab.com/ee/install/azure/
#   https://docs.bitnami.com/azure/get-started-charts-marketplace/
#   https://bitnami.com/stack/mongodb/helm
# User settings
timestamp=$(date +"%m%d%Y%H%M")
SUBSCRIPTION_NAME="gopal-pay-as-you-go"
RESOURCE_GROUP_NAME="mdb-rg-$timestamp"
AKS_CLUSTER="mdb-cluster"
AKS_NODE_COUNT=2
AKS_NODE_VM_SIZE="Standard_D4s_v3"
AKS_NAMESPACE="default"
AZURE_REGION="westus"
PUBLIC_KEY="$(tr -d '\n' < ~/.ssh/id_rsa.pub)"
MONGO_PUB_IP_DNS_PREFIX="mdb-${RESOURCE_GROUP_NAME}"
MONGO_PUBLIC_IP_RESOURCE_NAME="mongodb-ip"
# ========= Do not change beyond this point =============
# Login to Azure and capture ID of the required subscription account
SUBSCRIPTION_ID=$(az login | jq -r --arg SUBNAME "$SUBSCRIPTION_NAME" '.[] | select( .name == $SUBNAME) | .id')
SUB_DOMAIN="${MONGO_PUB_IP_DNS_PREFIX}.${AZURE_REGION}"
MONGO_DNS_NAME="${SUB_DOMAIN}.cloudapp.azure.com"
az account set --subscription "$SUBSCRIPTION_ID"
az configure --defaults group="$RESOURCE_GROUP_NAME"
# Create Resource group
echo "Creating resource group: $RESOURCE_GROUP_NAME"
az group create -n "$RESOURCE_GROUP_NAME" -l $AZURE_REGION
# Create AKS Cluster 
echo "Creating AKS cluster: ${AKS_CLUSTER} on resource group: $RESOURCE_GROUP_NAME"
node_resource_group=$(az aks create \
    --resource-group "$RESOURCE_GROUP_NAME" \
    --name $AKS_CLUSTER \
    --node-count $AKS_NODE_COUNT \
    --node-vm-size $AKS_NODE_VM_SIZE \
    --generate-ssh-keys | \
    jq -r '.nodeResourceGroup')

echo "The node resource group created by AKS is: $node_resource_group"
# Install Kubectl, if not available
STATUS=0
which -s kubectl;STATUS=$?
if [ $STATUS -eq 1 ];then
    echo -e "\n kubectl is unavailable. Installing..."
    sudo az aks install-cli
fi
# Install helm, if not available
STATUS=0
which -s helm;STATUS=$?
if [ $STATUS -eq 1 ];then
    KERNEL_NAME=$(uname -s)
    if [ "${KERNEL_NAME}" = "Darwin" ]; then
        brew install helm
    else
        # shellcheck disable=SC2164
        cd ~
        curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get-helm-3 > get_helm.sh
        chmod 700 get_helm.sh
        # Add this to PATH in .bashrc
    fi
fi
# Run below command to make connection to cluster from desktop and synch-up credentials.
echo "Connecting to Cluster: ${AKS_CLUSTER} on resource group: $RESOURCE_GROUP_NAME"
az aks get-credentials -g "$RESOURCE_GROUP_NAME" -n $AKS_CLUSTER
# Deploy Mongo DB runner
helm repo add azure-marketplace https://marketplace.azurecr.io/helm/v1/repo
helm repo update
helm install my-release azure-marketplace/mongodb
# Get the Root Password
MONGODB_ROOT_PASSWORD=$(kubectl get secret --namespace default my-release-mongodb -o jsonpath="{.data.mongodb-root-password}" | base64 --decode)
export MONGODB_ROOT_PASSWORD
# Create a client container for Mongo DB
kubectl run --namespace default my-release-mongodb-client --rm --tty -i --restart='Never' --env="MONGODB_ROOT_PASSWORD=$MONGODB_ROOT_PASSWORD" --image marketplace.azurecr.io/bitnami/mongodb:4.4.6-debian-10-r8 --command -- bash

#========= IMPORTANT INFORMATION ==================
#MongoDB can be accessed from within your cluster on the following DNS name and port (27017):
# my-release-mongodb.default.svc.cluster.local

#To get the root password run:
# export MONGODB_ROOT_PASSWORD=$(kubectl get secret --namespace default my-release-mongodb -o jsonpath="{.data.mongodb-root-password}" | base64 --decode)

#To connect to your database, create a MongoDB(R) client container:
# kubectl run --namespace default my-release-mongodb-client --rm --tty -i --restart='Never' --env="MONGODB_ROOT_PASSWORD=$MONGODB_ROOT_PASSWORD" --image marketplace.azurecr.io/bitnami/mongodb:4.4.6-debian-10-r8 --command -- bash

#Then, run the following command:
# mongo admin --host "my-release-mongodb" --authenticationDatabase admin -u root -p $MONGODB_ROOT_PASSWORD

#To connect to your database from outside the cluster execute the following commands:
# kubectl port-forward --namespace default svc/my-release-mongodb 27017:27017 &
# mongo --host 127.0.0.1 --authenticationDatabase admin -p $MONGODB_ROOT_PASSWORD