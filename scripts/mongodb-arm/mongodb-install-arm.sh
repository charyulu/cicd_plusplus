#/bin/bash
#Reference: https://docs.gitlab.com/ee/install/azure/
# User settings
timestamp=$(date +"%m%d%Y%H%M")
SUBSCRIPTION_NAME="gopal-pay-as-you-go"
RESOURCE_GROUP_NAME="db-rg-$timestamp"
AZURE_LOCATION="westus"
# Note: If public key isn't available, create one. 
#       https://git-scm.com/book/en/v2/Git-on-the-Server-Generating-Your-SSH-Public-Key
PUBLIC_KEY="$(tr -d '\n' < ~/.ssh/id_rsa.pub)"
MONGO_VM_ADMIN_USER="charyulu"
# The below DNS prefix must be Unique. Otherwise script will fail.
MONGO_PUB_IP_DNS_PREFIX="mongo-${RESOURCE_GROUP_NAME}"
# The below settings are default values. No need to change unless required/ know what you are doing.
MONGO_PUBLIC_IP_RESOURCE_NAME="mongodb-ip"
MONGO_VM_NAME="mongodb"
# ========= Do not change beyond this point =============
# Login to Azure and capture ID of the required subscription account
SUBSCRIPTION_ID=$(az login | jq -r --arg SUBNAME "$SUBSCRIPTION_NAME" '.[] | select( .name == $SUBNAME) | .id')
SUB_DOMAIN="${MONGO_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}"
MONGO_DNS_NAME="${SUB_DOMAIN}.cloudapp.azure.com"
az account set --subscription $SUBSCRIPTION_ID
az configure --defaults group=$RESOURCE_GROUP_NAME
az group create -l $AZURE_LOCATION -n $RESOURCE_GROUP_NAME
echo -e "\n Accepting Azure market place terms and conditions for CentOS image"
# NOTE: To get URN of a specific centos image, run below command: 
#       az vm image list -f CentOS --all | grep mongodb-on-centos-75
az vm image terms accept --urn "apps-4-rent:mongodb-on-centos-75:mongodb-on-centos-75:2.0.0"
# Trigger deployment on the required Resource group
echo -e "\n Gitlab deployment is in progress...\n"
templateFile="template.json"
ParameterFile="parameters.json"
today=$(date +"%b%d%Y-%H%M")
DeploymentName="gitlab-deploy-"$today
az deployment group create \
 --name $DeploymentName \
 --template-file $templateFile \
 --parameters $ParameterFile location=${AZURE_LOCATION} adminUsername=${MONGO_VM_ADMIN_USER} adminPublicKey="${PUBLIC_KEY}" 
# Check deployment status
PROVISION_STATUS=$(az deployment group show -g $RESOURCE_GROUP_NAME -n $DeploymentName | jq -r '.properties.provisioningState')
DEPLOY_STATUS=$(az deployment group show -g $RESOURCE_GROUP_NAME -n $DeploymentName | jq -r '.properties.error.code')
if [[ $PROVISION_STATUS == "Failed" ]];then
    az deployment group show -g $RESOURCE_GROUP_NAME -n $DeploymentName | jq -r '.properties.error | .code, .details[]'
    echo -e "\n Gitlab Deployment is Failed... Exiting";exit 128
else
    echo -e "Deployment $DeploymentName on resource Group $RESOURCE_GROUP_NAME is $PROVISION_STATUS..."
fi
echo -e "\n Gitlab configuration is in progress...\n"
# Add prefix to Gitlab Public IP DNS name.
echo -e "Here are the DNS and Public IP details: \n"
echo $(az network public-ip update -g ${RESOURCE_GROUP_NAME} -n ${MONGO_PUBLIC_IP_RESOURCE_NAME} --dns-name ${MONGO_PUB_IP_DNS_PREFIX} --allocation-method Static) | jq -r '[.dnsSettings, .ipAddress]'
# Open DB port and configure Mongo DB
echo -e "Opening Mongo DB Port - Inbound to VM: \n"
az vm open-port -g ${RESOURCE_GROUP_NAME} -n ${MONGO_VM_NAME} --port 27017 --priority 200
echo -e "Configuring Mango DB and restarting the deamon.\n"
az vm run-command invoke -g ${RESOURCE_GROUP_NAME} -n ${MONGO_VM_NAME} --command-id RunShellScript --scripts "sudo sed -i 's/bindIp.*$/bindIp: 0.0.0.0/g' /etc/mongod.conf; sudo systemctl restart  mongod; sudo cat /var/log/mongodb/mongod.log"
