#!/bin/sh
# Step -1: Install homebrew, if not available
# Reference: https://brew.sh/
#/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# Step -2: Install tap
#Reference: https://learn.hashicorp.com/tutorials/terraform/install-cli?in=terraform/azure-get-started#install-terraform
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
# Step - 2a [Optional] - Update Terraform
brew update
brew upgrade hashicorp/tap/terraform
# Step - 3: Verify installation
terraform --version
terraform -help
terraform -help plan

# Step -4: Install auto completion
touch ~/.bashrc  # NOTE: Usually Mac will have softlink to bashrc inside the bash_profile file.
terraform -install-autocomplete

# Step -5: Install nginx
open -a Docker
mkdir -p learn-terraform-docker-container
cd learn-terraform-docker-container
cp ../main.tf .
terraform init
terraform apply
# Step - 5a: Verify nginx
docker ps | grep tutorial
curl localhost:8000

# Step - 5b: Check the files (tfstate, etc. ) created by terraform
ls -alR 
# Step -6: Destroy nginx container
terraform destroy
