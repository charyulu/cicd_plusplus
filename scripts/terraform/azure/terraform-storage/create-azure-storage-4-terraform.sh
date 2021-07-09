#!/bin/bash
# References: 
#       https://docs.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage

# Step -1: Configure storage account
# Reference: https://docs.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage#configure-storage-account
TIMESTAMP=$(date +"%m%d%Y%H%M")
RESOURCE_GROUP_NAME="trfm-state-rg"
#STORAGE_ACCOUNT_NAME="trfm_state$RANDOM"
STORAGE_ACCOUNT_NAME="trfmstore"
CONTAINER_NAME="trfmstorecontr"
AZ_LOCATION="westus"
AZ_KEYVAULT_NAME="gskeyvault$RANDOM"
AZ_KEYVAULT_ENTRY="terraform-backend-key"

# Create resource group
az group create --name $RESOURCE_GROUP_NAME --location $AZ_LOCATION

# Create storage account
az storage account create --resource-group $RESOURCE_GROUP_NAME --name $STORAGE_ACCOUNT_NAME --sku Standard_LRS --encryption-services blob

# Get storage account key
ACCOUNT_KEY=$(az storage account keys list --resource-group $RESOURCE_GROUP_NAME --account-name $STORAGE_ACCOUNT_NAME --query '[0].value' -o tsv)

# Create blob container
az storage container create --name $CONTAINER_NAME --account-name $STORAGE_ACCOUNT_NAME --account-key $ACCOUNT_KEY

echo "storage_account_name: $STORAGE_ACCOUNT_NAME"
echo "container_name: $CONTAINER_NAME"

# Step -2: Configure state back end
# Reference: https://docs.microsoft.com/en-us/azure/developer/terraform/store-state-in-azure-storage#configure-state-back-end
## Create Env var to protect storage access key.
export ARM_ACCESS_KEY=${ACCOUNT_KEY}

# Create Azure key vault
az keyvault create --name ${AZ_KEYVAULT_NAME} --resource-group ${RESOURCE_GROUP_NAME} --location ${AZ_LOCATION}

# Add a secret to keyvault
az keyvault secret set --vault-name ${AZ_KEYVAULT_NAME} --name ${AZ_KEYVAULT_ENTRY} --value ${ARM_ACCESS_KEY}

## Retrieve secret from Azure key vault
export ARM_ACCESS_KEY=$(az keyvault secret show --name  ${AZ_KEYVAULT_ENTRY} --vault-name ${AZ_KEYVAULT_NAME} --query value -o tsv)
echo "${ARM_ACCESS_KEY}"

# Run sample terraform manifest
terraform init
terraform apply -auto-approve -json
