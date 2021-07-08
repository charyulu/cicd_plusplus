# References:
#   https://registry.terraform.io/browse/providers
#   https://registry.terraform.io/browse/modules
#   https://registry.terraform.io/providers/hashicorp/azurerm/latest
# Configure the Azure provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.65"
    }
  }

  required_version = ">= 0.14.9"
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "rg" {
  name     = "gs-tf-rg"
  location = "westus"
}
