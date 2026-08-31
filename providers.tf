provider "azurerm" {
  features {}

  # Leave unset to fall back to the ARM_SUBSCRIPTION_ID environment variable.
  subscription_id = var.subscription_id
}

# Required by the Azure Verified Modules used below.
provider "azapi" {
  subscription_id = var.subscription_id
}
