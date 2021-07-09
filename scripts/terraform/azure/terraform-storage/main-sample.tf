terraform {
  backend "azurerm" {
    resource_group_name   = "trfm-state-rg"
    storage_account_name  = "trfmstore"
    container_name        = "trfmstorecontr"
    key                   = "terraform.tfstate"
  }
}

# Configure the Azure provider
provider "azurerm" { 
  features {}
}

resource "azurerm_resource_group" "state-trfm" {
  name     = "state-trfm"
  location = "westus"
}
