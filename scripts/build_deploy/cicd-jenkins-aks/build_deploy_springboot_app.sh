#!/bin/bash
# Synopsis: This script takes code from github, build and deploy through Jenkins to AKS
# References:
#       https://docs.microsoft.com/en-us/azure/developer/jenkins/deploy-from-github-to-aks
#       https://github.com/Azure-Samples/azure-voting-app-redis
#       https://docs.microsoft.com/en-us/azure/aks/kubernetes-walkthrough?WT.mc_id=none-github-nepeters
#       https://docs.microsoft.com/en-us/azure/aks/tutorial-kubernetes-prepare-app?WT.mc_id=none-github-nepeters
#       Additional references: https://docs.microsoft.com/en-us/azure/developer/jenkins/plug-ins-for-azure
# User settings
function define_vars() {
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
    PUBLIC_KEY="$(tr -d '\n' <~/.ssh/id_rsa.pub)"
    export PUBLIC_KEY
    export PROJ_BASE_DIR="/Users/sudarsanam/Documents/prasad/cicd_plusplus/scripts/build_deploy/cicd-jenkins-aks"
    export IMAGE_NAME="azure-vote-front"
    export POD_NAME="${IMAGE_NAME}"
    export JENKINS_VM_NAME="cicd-jenk-vm"
    export JENKINS_PUBLIC_IP_RESOURCE_NAME="${JENKINS_VM_NAME}PublicIP"
    export JENKINS_VM_ADMIN_USER="charyulu" # NOTE: Add same value in
    export JENKINS_PUB_IP_DNS_PREFIX="jenkins-${JENKINS_VM_ADMIN_USER}"
    # Give absolute path to .kube/config
    export KUBE_CONFIG_FILE="/Users/sudarsanam/.kube/config"
    # Login to Azure and capture ID of the required subscription account
    SUBSCRIPTION_ID=$(az login | jq -r --arg SUBNAME "$SUBSCRIPTION_NAME" '.[] | select( .name == $SUBNAME) | .id')
    export SUBSCRIPTION_ID
}
# Check if resource group existing. If not, create a new resource group.
check_and_create_resource_group () {

    QUERY_OUTPUT=$(az group show -n "$RESOURCE_GROUP_NAME" --subscription $SUBSCRIPTION_NAME --query name -o tsv)
    if [[ "$QUERY_OUTPUT" != "$RESOURCE_GROUP_NAME" ]]; then
        echo "Resource Group: $RESOURCE_GROUP_NAME not found... Creating it"
        az group create --name "$RESOURCE_GROUP_NAME" --location $AZURE_REGION
    else
        echo "Resource Group: $RESOURCE_GROUP_NAME already existing."
    fi
}

# Prerequisites:
# Azure container registry (ACR) credential helper. (https://github.com/Azure/acr-docker-credential-helper)
# Azure CLI
# Java 8/ 11
# Maven, Git & docker

# Function: Install and deploy Jenkins on VM
# Reference: https://github.com/Azure-Samples/azure-voting-app-redis/tree/master/jenkins-tutorial

function bootstrap_jenkins_vm() {
    # Check & Create a resource group.
    check_and_create_resource_group
    # Create a new virtual machine, this creates SSH keys if not present ans install Jenkins using VM init script
    # Reference: https://docs.microsoft.com/en-us/azure/developer/jenkins/configure-on-linux-vm
    az vm create --resource-group "$RESOURCE_GROUP_NAME" --name $JENKINS_VM_NAME --public-ip-sku Standard --admin-username $JENKINS_VM_ADMIN_USER --image UbuntuLTS --generate-ssh-keys --custom-data ./bootstrap_jenkins_vm.txt
    echo -e "\n Waiting on VM to start Jenkins..."; sleep 30

    # Use CustomScript extension to install toolset (jenkins, JDK, Docker, Azure CLI, Kubectl).
    #  IMPORTANT NOTE: 
    #       1. This method requires the script file in the github to be Public. 
    #       2. This option never worked successfully.
    #       3. So, went ahead with above "az vm create" command with an additional option --custom-data.
    # Reference: https://docs.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-linux
    #az vm extension set --publisher Microsoft.Azure.Extensions --version 2.0 --name CustomScript --vm-name $JENKINS_VM_NAME --resource-group "$RESOURCE_GROUP_NAME" --settings '{"fileUris": ["https://raw.githubusercontent.com/charyulu/cicd_plusplus/main/scripts/build_deploy/cicd-jenkins-aks/config-jenkins.sh"],"commandToExecute": "./config-jenkins.sh"}'
    #echo -e "\n Waiting after VM configuration..."; sleep 240

    # Open port 80 to allow web traffic to host.
    az vm open-port --port 80 --resource-group "$RESOURCE_GROUP_NAME" --name $JENKINS_VM_NAME --priority 101

    # Open port 22 to allow ssh traffic to host.
    az vm open-port --port 22 --resource-group "$RESOURCE_GROUP_NAME" --name $JENKINS_VM_NAME --priority 102

    # Open port 8080 to allow web traffic to host.
    az vm open-port --port 8080 --resource-group "$RESOURCE_GROUP_NAME" --name $JENKINS_VM_NAME --priority 103
    echo -e "\n Waiting after VM configuration..."; sleep 240

    # Get public IP
    JENKINS_VM_PUBLIC_IP=$(az vm list-ip-addresses --resource-group "$RESOURCE_GROUP_NAME" --name $JENKINS_VM_NAME --query [0].virtualMachine.network.publicIpAddresses[0].ipAddress -o tsv)
    echo -e "\n JENKINS_VM_PUBLIC_IP = $JENKINS_VM_PUBLIC_IP"
    # Add prefix to Gitlab Public IP DNS name.
    echo -e "Here are the DNS and Public IP details: \n"
    az network public-ip update -g "${RESOURCE_GROUP_NAME}" -n ${JENKINS_PUBLIC_IP_RESOURCE_NAME} --dns-name ${JENKINS_PUB_IP_DNS_PREFIX} --allocation-method Static | jq -r '[.dnsSettings, .ipAddress]'

    # Copy Kube config file to Jenkins
    ssh -o "StrictHostKeyChecking no" $JENKINS_VM_ADMIN_USER@"$JENKINS_VM_PUBLIC_IP" sudo chmod 777 /var/lib/jenkins
    yes | scp $KUBE_CONFIG_FILE $JENKINS_VM_ADMIN_USER@"$JENKINS_VM_PUBLIC_IP":/var/lib/jenkins/config
    ssh -o "StrictHostKeyChecking no" $JENKINS_VM_ADMIN_USER@"$JENKINS_VM_PUBLIC_IP" sudo chmod 777 /var/lib/jenkins/config

    # Get Jenkins Unlock Key
    JENKINS_URL="http://$JENKINS_VM_PUBLIC_IP:8080"
    echo -e "Open Jenkins in browser at: $JENKINS_URL"
    echo -e "Enter the following to Unlock Jenkins:"
    ssh -o "StrictHostKeyChecking no" $JENKINS_VM_ADMIN_USER@"$JENKINS_VM_PUBLIC_IP" sudo cat /var/lib/jenkins/secrets/initialAdminPassword
    echo -e "\n\n Take above said steps and press any key to continue..."
    read -r
}
function setup_aks_application() {
    # Fork the project https://github.com/Azure-Samples/azure-voting-app-redis into personal github account
    rm -rf azure-voting-app-redis
    git clone git@github.com:charyulu/azure-voting-app-redis.git
    # shellcheck disable=SC2164
    cd azure-voting-app-redis
    # Download, create and start Docker images of application Front end and backend
    docker-compose up -d
    az account set --subscription "$SUBSCRIPTION_ID"
    # check & Create Resource group
    check_and_create_resource_group
    # Create private azure container registery
    az acr create --resource-group "$RESOURCE_GROUP_NAME" --location $AZURE_REGION \
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
        --resource-group "$RESOURCE_GROUP_NAME" \
        --name $AKS_CLUSTER \
        --node-count $AKS_NODE_COUNT \
        --node-vm-size $AKS_NODE_VM_SIZE \
        --attach-acr $ACR_NAME \
        --dns-name-prefix $AKS_DNS_NAME_PREFIX --generate-ssh-keys |
        jq -r '.nodeResourceGroup')
    # Install Kubectl, if not available
    STATUS=0
    which -s kubectl
    STATUS=$?
    if [ $STATUS -eq 1 ]; then
        echo -e "\n kubectl is unavailable. Installing..."
        az aks install-cli
    fi
    echo "The node resource group created by AKS is: $node_resource_group"
    # Run below command to make connection to cluster from desktop and synch-up credentials.
    echo "Downloading config and connecting to Cluster: ${AKS_CLUSTER} on resource group: $RESOURCE_GROUP_NAME"
    az aks get-credentials -g "$RESOURCE_GROUP_NAME" -n $AKS_CLUSTER --overwrite-existing

    # Update image URI in kubernetes deployment manifest with ACR created above
    sed -i '' -e "s/mcr.microsoft.com\/azuredocs/${ACR_NAME}.azurecr.io/" ./azure-vote-all-in-one-redis.yaml
    # Option - 1: Deploy application on AKS - In declarative mode - Using manifests
    kubectl apply -f ./azure-vote-all-in-one-redis.yaml
    echo -e "\n Waiting for POD to come up...";sleep 60
    kubectl get service azure-vote-front

    # Option -2: Deploy application on AKS -  In Imperfative mode - Using "kubectl run"
    #kubectl run ${POD_NAME} --image=${ACR_NAME}.azurecr.io/${IMAGE_NAME}:latest
    #Expose the application (container) externally
    #kubectl expose pod ${POD_NAME} --type=LoadBalancer --port=80 --target-port=8080
    #echo -e "\n Waiting for POD to come up..."
    #sleep 30
    # Get the External IP of the cluster:
    CLUSTER_PUBLIC_IP=$(kubectl get services -o=jsonpath='{.items[*].status.loadBalancer.ingress[0].ip}')
    echo -e "\n CLUSTER_PUBLIC_IP = $CLUSTER_PUBLIC_IP \nAccess application on: http://${CLUSTER_PUBLIC_IP}"

}

case "$1" in 
    "aks")
        # Set up the cluster and application
        echo -e "\n Setting up the cluster and application...."
        define_vars
        setup_aks_application
        ;;
    "jenkins")
        # Create VM, install and configure Jenkins
        echo -e "\n Bootstrapping Jenkins VM...."
        define_vars
        bootstrap_jenkins_vm
        ;;
    *)
        echo -e "\n No arguments passed. So, proceeding with full run...\n"
        define_vars
        echo -e "\n Bootstrapping Jenkins VM...."
        bootstrap_jenkins_vm
        echo -e "\n Setting up cluster and application...."
        setup_aks_application
    ;;
esac


#CLEAN-UP - all resources created
#NODE_RG=$(az aks show --name $AKS_CLUSTER --resource-group $RESOURCE_GROUP_NAME | jq -r '.nodeResourceGroup')
#echo "Deleting resource group $NODE_RG"
#az group delete -n $RESOURCE_GROUP_NAME --no-wait -y
#echo "Deleting mode resource group $NODE_RG"
#az group delete -n $NODE_RG --no-wait -y
