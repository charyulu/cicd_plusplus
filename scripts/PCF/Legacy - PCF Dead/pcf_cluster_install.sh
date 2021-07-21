#!/bin/bash
# Synopsis: This script takes care of creating Tanzu Application Service (formerly Pivotal Cloud Foundry - PCF)
# Reference: https://docs.microsoft.com/en-us/azure/cloudfoundry/create-cloud-foundry-on-azure#get-the-pivotal-network-token
#            
timestamp=$(date +"%m%d%Y%H%M")
SUBSCRIPTION_NAME="gopal-pay-as-you-go"
RESOURCE_GROUP_NAME="pcf-rg-$timestamp"
AKS_CLUSTER="pcf-cluster"
AKS_NODE_COUNT=2
PCF_VM_SIZE="Standard_DS2_v2"
AKS_NAMESPACE="default"
AZURE_REGION="westus"
PUBLIC_KEY="$(tr -d '\n' < ~/.ssh/id_rsa.pub)"
# Get Pivotal network token. Refer: https://docs.microsoft.com/en-us/azure/cloudfoundry/create-cloud-foundry-on-azure#get-the-pivotal-network-token
# IMPORTANT NOTE: Do not take "LEGACY API TOKEN" which is deprecated. Take "UAA API TOKEN" instead and save the token.
PIVOTAL_ID="3c9998b07fe24558b82407edcb9563b5-r"
# Login to Azure and capture ID of the required subscription account
LOGIN_OUPTUT="$(az login)"
SUBSCRIPTION_ID=$(echo "$LOGIN_OUPTUT" | jq -r --arg SUBNAME "$SUBSCRIPTION_NAME" '.[] | select( .name == $SUBNAME) | .id')
TENANT_ID=$(echo "$LOGIN_OUPTUT" | jq -r --arg SUBNAME "$SUBSCRIPTION_NAME" '.[] | select( .name == $SUBNAME) | .tenantId')
#Set default subscription
az account set --subscription "$SUBSCRIPTION_ID"
# Create Resource group
echo "Creating resource group: $RESOURCE_GROUP_NAME"
az group create -n "$RESOURCE_GROUP_NAME" -l $AZURE_REGION

#Create an Azure Active Directory application for your PCF
## Step -1: Create random Password using openssl random
AD_PASSWORD=$(openssl rand -base64 12)
PCF_HOME_PAGE="http://charyulu.app.net/pcf"
#Create a web application, web API or native application
AD_APP_CREATE_OUTPUT=$(az ad app create --display-name "Svc Principal for OpsManager" --password "${AD_PASSWORD}" --homepage "${PCF_HOME_PAGE}" --identifier-uris "${PCF_HOME_PAGE}")
APP_ID="$(echo "${AD_APP_CREATE_OUTPUT}" | jq -r '.appId')"

#Create a service principal with new app ID.
az ad sp create --id "${APP_ID}"

#Set the permission role of your service principal as a Contributor.
az role assignment create --assignee "${PCF_HOME_PAGE}" --role "Contributor" -g "$RESOURCE_GROUP_NAME"

# Verify that you can successfully sign in to your service principal by using the app ID, password, and tenant ID.
LOGIN_STATUS=$(az login --service-principal -u "${APP_ID}" -p "${AD_PASSWORD}"  --tenant "${TENANT_ID}" | jq -r ' .[] | .state')
if [[ "${LOGIN_STATUS}" != "Enabled" ]];then
    echo -e "\n Login to service principal failed... Exiting"
    exit 128
fi
echo -e "
{
    \"subscriptionID\": \"${SUBSCRIPTION_ID}\",
    \"tenantID\": \"${TENANT_ID}\",
    \"clientID\": \"${APP_ID}\",
    \"clientSecret\": \"${AD_PASSWORD}\"
}
" > "./app_info.json"

