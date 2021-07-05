#/bin/bash
#Reference: https://docs.gitlab.com/ee/install/azure/
# User settings
SUBSCRIPTION_NAME="gopal-pay-as-you-go"
RESOURCE_GROUP_NAME="gs-rg"
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

# ======= Start - Edit files on the VM ========
# Cleanup the host name from ~/.ssh/known_hosts file to get rid of spoofing error.
ssh-keygen -R ${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com
# ====================================================================================================
# The Below Steps are not working. Currently they were left as manual changes. Will be revisited later
# ====================================================================================================
# The below steps are to change the Gitlab external URL, turn off nginx setting to avoid picking up wrong certs. Below is the sequence 
#       Copy /etc/gitlab/gitlab.rb to ~/ on VM,
#       Make changes (Replace external_url setting with DNS name
#       Turn off nginix cert settings to avoid picking incorrect certs
#       copy back updated file to /etc/gitlab/gitlab.rb on VM
#ssh -o StrictHostKeyChecking=no ${GITLAB_VM_ADMIN_USER}@${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com \
#'sudo cp /etc/gitlab/gitlab.rb ~/.; sudo chmod 666 ~/gitlab.rb'
#ssh ${GITLAB_VM_ADMIN_USER}@${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com \
#"sed -i 's/127.0.0.1/${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com/g; /^nginx.*redirect_http_to_https.*$/ s/^/#/; /^nginx.*ssl_certificate.*$/ s/^/#/' ~/gitlab.rb"
#ssh ${GITLAB_VM_ADMIN_USER}@${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com 'sudo cp ~/gitlab.rb /etc/gitlab/gitlab.rb'
echo -e "\n ssh ${GITLAB_VM_ADMIN_USER}@${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com \n Make changes to /etc/gitlab/gitlab.rb file and press any key to proceed...\n";read
# ======= End - Edit files on the VM ========
echo -e "\n Gitlab reconfigure is in progress...\n"
#echo -e "\n Connect to: ssh ${GITLAB_VM_ADMIN_USER}@${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com \n Update file: /etc/gitlab/gitlab.rb\n NOTE: external_url https://gitlab-gs-rg.westus.cloudapp.azure.com" 
#echo -e "\n Press any key to proceed...";read
ssh ${GITLAB_VM_ADMIN_USER}@${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com 'sudo gitlab-ctl reconfigure'

# Get Password of Gitlab from Bitnami log: https://docs.bitnami.com/azure/faq/get-started/find-credentials/
echo -e "\n\nTrying to get VM's Boot diagnostics logs to find root password from. If it fails, get the password manually from Azure portal\n\n"
# Refer: https://docs.bitnami.com/azure/faq/get-started/find-credentials/
az vm boot-diagnostics get-boot-log -n ${GITLAB_VM_NAME} -g ${RESOURCE_GROUP_NAME}

echo -e "\n Login to Gitlab: https://${GITLAB_PUB_IP_DNS_PREFIX}.${AZURE_LOCATION}.cloudapp.azure.com"
