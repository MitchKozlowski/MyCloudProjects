# Declares which provider(s) Terraform needs and pins their versions.
# Similar in spirit to requirements.txt pinning package versions - without
# this, a Terraform run six months from now could pull a newer provider
# version with breaking changes.
terraform {
  required_version = ">= 1.7.0"

  # Remote state: instead of a local terraform.tfstate file that only
  # exists on whichever machine ran `terraform apply`, state now lives in
  # the Azure Storage container we created. This is what lets GitHub
  # Actions (an ephemeral runner with no memory between runs) and your
  # laptop both work against the SAME state safely, without either one
  # thinking resources don't exist yet and trying to recreate them.
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "tfstateasteroidwatch"
    container_name        = "tfstate"
    key                   = "asteroid-watch.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.116"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# The azurerm provider is what actually knows how to talk to Azure's API.
# `features {}` is required even when empty - it's where you'd opt into
# provider-wide behaviors if needed later.
#
# Authentication: we're NOT putting credentials here. The provider picks up
# your identity automatically from `az login` (same idea as the AWS
# provider using your `aws configure` credentials/profile). Later, in
# GitHub Actions, this will instead authenticate via OIDC federated
# credentials - no long-lived secret stored anywhere.
provider "azurerm" {
  features {}
}
