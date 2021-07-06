#/bin/bash
#Reference: https://docs.gitlab.com/ee/install/azure/
# User settings
timestamp=$(date +"%m%d%Y%H%M")
SUBSCRIPTION_NAME="gopal-pay-as-you-go"
RESOURCE_GROUP_NAME="bit-rg-$timestamp"
AZURE_LOCATION="westus"
# Note: If public key isn't available, create one. 
#       https://git-scm.com/book/en/v2/Git-on-the-Server-Generating-Your-SSH-Public-Key
PUBLIC_KEY="$(tr -d '\n' < ~/.ssh/id_rsa.pub)"
GITLAB_VM_ADMIN_USER="charyulu"
# The below DNS prefix must be Unique. Otherwise script will fail.
GITLAB_PUB_IP_DNS_PREFIX="gitlab-${RESOURCE_GROUP_NAME}"
# The below settings are default values. No need to change unless required/ know what you are doing.
GITLAB_PUBLIC_IP_RESOURCE_NAME="gitlab-ip"
GITLAB_VM_NAME="gitlab"
# ========= Do not change beyond this point =============
# Login to Azure and capture ID of the required subscription account
SUBSCRIPTION_ID=$(az login | jq -r --arg SUBNAME "$SUBSCRIPTION_NAME" '.[] | select( .name == $SUBNAME) | .id')
SUB_DOMAIN="${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}"
GITLAB_DNS_NAME="${SUB_DOMAIN}.cloudapp.azure.com"
az account set --subscription $SUBSCRIPTION_ID
az configure --defaults group=$RESOURCE_GROUP_NAME
az group create -l $AZURE_LOCATION -n $RESOURCE_GROUP_NAME
#echo -e "\n Waiting after Resouce Group creation...\n\n";sleep 10
# Trigger deployment on the required Resource group
echo -e "\n Gitlab deployment is in progress...\n"
templateFile="template.json"
ParameterFile="parameters.json"
today=$(date +"%b%d%Y-%H%M")
DeploymentName="gitlab-deploy-"$today
az deployment group create \
 --name $DeploymentName \
 --template-file $templateFile \
 --parameters $ParameterFile location=${AZURE_LOCATION} adminUsername=${GITLAB_VM_ADMIN_USER} adminPublicKey="${PUBLIC_KEY}" 
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
echo $(az network public-ip update -g ${RESOURCE_GROUP_NAME} -n ${GITLAB_PUBLIC_IP_RESOURCE_NAME} --dns-name ${GITLAB_PUB_IP_DNS_PREFIX} --allocation-method Static) | jq -r '[.dnsSettings, .ipAddress]'
# Run below commands from server commandline
echo -e "\n Open another command window and run below commands in the sequrence\n"
echo -e "ssh ${GITLAB_VM_ADMIN_USER}@${GITLAB_DNS_NAME}"
echo -e "sudo /opt/bitnami/apps/gitlab/bnconfig --machine_hostname ${GITLAB_DNS_NAME}"
echo -e "sudo mv /opt/bitnami/apps/gitlab/bnconfig /opt/bitnami/apps/gitlab/bnconfig.stopped"
echo -e "sudo vi /etc/gitlab/gitlab.rb"
echo -e "Comment out: \n nginx['redirect_http_to_https'] = true \n nginx['ssl_certificate'] = \"/etc/gitlab/ssl/server.crt\" \n nginx['ssl_certificate_key'] = \"/etc/gitlab/ssl/server.key\""
echo -e "sudo gitlab-ctl reconfigure"
echo -e "Connect to Azure Portal, Login, and anf got to respective resource-Group/VM/Boot Diagnostics/ Select Serial Logs"
echo -e "Scroll down the log and Get Root Password - To use to login to Gitlab Portal at https://${GITLAB_DNS_NAME}"
