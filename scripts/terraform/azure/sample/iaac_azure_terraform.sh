#!/bin/sh
# Step -1: Install azure cli
# References: 
#       https://learn.hashicorp.com/tutorials/terraform/azure-build
#       https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
brew update && brew install azure-cli
# Step -2: azure login
az login
## Step -3: Write configuration
mkdir learn-terraform-azure
cd learn-terraform-azure
cp ../main.tf .
## Step -4: Format & Validate the configuration
terraform init
terraform fmt
terraform validate
## Step -5: Create the infrastructure on Azure
terraform apply -auto-approve -json
# Step - 5a: Inspect the state
terraform show
terraform state list
# Step - 5b: Check the files (tfstate, etc. ) created by terraform
#ls -alR 
#echo -e "Press any key to destroy the Infrastructure...";read
# Step -6: Destroy nginx container
#terraform destroy
