#/bin/bash
#Reference: https://docs.gitlab.com/ee/install/azure/
# User settings
SUBSCRIPTION_NAME="gopal-pay-as-you-go"
RESOURCE_GROUP_NAME="gs-rg"
AZURE_LOCATION="westus"
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
az account set --subscription $SUBSCRIPTION_ID
az configure --defaults group=$RESOURCE_GROUP_NAME
az group create -l $AZURE_LOCATION -n $RESOURCE_GROUP_NAME
# Trigger deployment on the required Resource group
templateFile="template.json"
ParameterFile="parameters.json"
today=$(date +"%d-%b-%Y")
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
else
    echo -e "Deployment $DeploymentName on resource Group $RESOURCE_GROUP_NAME is $PROVISION_STATUS..."
fi
# Add prefix to Gitlab Public IP DNS name.
echo -e "Here are the DNS and Public IP details: \n"
echo $(az network public-ip update -g ${RESOURCE_GROUP_NAME} -n ${GITLAB_PUBLIC_IP_RESOURCE_NAME} --dns-name ${GITLAB_PUB_IP_DNS_PREFIX} --allocation-method Static) | jq -r '[.dnsSettings, .ipAddress]'

# ======= Start - Edit files on the VM ========
# This is to change the Gitlab externla URL, turn off nginx setting to avoid picking up wronf certs.
ssh -o StrictHostKeyChecking=no ${GITLAB_VM_ADMIN_USER}@${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com 'sudo sed -i "/^external_url.*$/ s/^/#/" /etc/gitlab/gitlab.rb'
EXTERNAL_URL="external_url \'https://${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com\'"
# In below command, "tee" with -a switch has to be used, since ">>" will not work. Refer: https://unix.stackexchange.com/questions/382946/getting-permission-denied-when-trying-to-append-text-onto-a-file-using-sudo
ssh ${GITLAB_VM_ADMIN_USER}@${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com 'sudo echo '${EXTERNAL_URL}' | sudo tee -a /etc/gitlab/gitlab.rb'
ssh ${GITLAB_VM_ADMIN_USER}@${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com 'sudo sed -i "/^nginx.*redirect_http_to_https.*$/ s/^/#/" /etc/gitlab/gitlab.rb'
ssh ${GITLAB_VM_ADMIN_USER}@${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com 'sudo sed -i "/^nginx.*ssl_certificate.*$/ s/^/#/" /etc/gitlab/gitlab.rb'
# ======= End - Edit files on the VM ========
# Re-configure Gitlab to take updated changes done above.
ssh ${GITLAB_VM_ADMIN_USER}@${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com 'sudo gitlab-ctl reconfigure'

# Get Password of Gitlab from Bitnami log: https://docs.bitnami.com/azure/faq/get-started/find-credentials/
echo -e "\n\nTrying to get VM's Boot diagnostics logs to find root password from. If it fails, get the password manually from Azure portal\n\n"
# Refer: https://docs.bitnami.com/azure/faq/get-started/find-credentials/
az vm boot-diagnostics get-boot-log -n ${GITLAB_VM_NAME} -g ${RESOURCE_GROUP_NAME}

