#/bin/bash
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
MONGO_PUB_IP_DNS_PREFIX="${RESOURCE_GROUP_NAME}"
MONGO_PUBLIC_IP_RESOURCE_NAME="mongodb-ip"
# ========= Do not change beyond this point =============
# Login to Azure and capture ID of the required subscription account
SUBSCRIPTION_ID=$(az login | jq -r --arg SUBNAME "$SUBSCRIPTION_NAME" '.[] | select( .name == $SUBNAME) | .id')
SUB_DOMAIN="${MONGO_PUB_IP_DNS_PREFIX}.${AZURE_REGION}"
MONGO_DNS_NAME="${SUB_DOMAIN}.cloudapp.azure.com"
az account set --subscription $SUBSCRIPTION_ID
az configure --defaults group=$RESOURCE_GROUP_NAME
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
    --node-public-ip-prefix-id ${MONGO_PUB_IP_DNS_PREFIX} \
    --generate-ssh-keys | \
    jq -r '.nodeResourceGroup')

echo "The node resource group created by AKS is: $node_resource_group"
# Install Kubectl, if not available
if which kubectl |& egrep -q ".*no kubectl.*";then
    echo -e "\n kubectl is unavailable. Installing..."
    sudo az aks install-cli
fi
# Install helm, if not available
if which helm |& egrep -q ".*no helm.*";then
    KERNEL_NAME=$(uname -s)
    if [ "${KERNEL_NAME}" = "Darwin" ]; then
        brew install helm
    else
        cd ~
        curl https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get-helm-3 > get_helm.sh
        chmod 700 get_helm.sh
        # Add this to PATH in .bashrc
    fi
fi
# Run below command to make connection to cluster from desktop and synch-up credentials.
echo "Connecting to Cluster: ${AKS_CLUSTER} on resource group: $RESOURCE_GROUP_NAME"
az aks get-credentials -g $RESOURCE_GROUP_NAME -n $AKS_CLUSTER
# Deploy Mongo DB runner
helm repo add azure-marketplace https://marketplace.azurecr.io/helm/v1/repo
helm repo update
helm install my-release azure-marketplace/mongodb

