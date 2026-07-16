# --- Unique naming ---
# Azure Container Registry names must be globally unique across ALL of
# Azure (like S3 bucket names in AWS) - "asteroidwatch" alone will almost
# certainly already be taken by someone. We generate a short random suffix
# once and reuse it everywhere, so re-running `terraform apply` doesn't
# generate a NEW random name each time (that would try to create a second
# registry instead of managing the same one).
resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  # ACR names: alphanumeric only, no hyphens allowed.
  acr_name = "${var.project_name}acr${random_id.suffix.hex}"
}

# --- Resource Group ---
# Think of this as the folder every other resource below lives in. Tearing
# down the whole project later is as simple as deleting this one resource
# group - everything inside it goes with it.
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location
}

# --- Azure Container Registry (ACR) ---
# Equivalent to an ECR repository. This is where your Docker image lives.
# Basic SKU is the cheapest tier - plenty for a portfolio project.
resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"

  # admin_enabled = false is the more secure default - we authenticate
  # pushes with `az acr login` (your own Azure identity) instead of a
  # shared admin username/password. The Container App itself will pull
  # using a managed identity (see below), not these admin credentials.
  admin_enabled = false
}

# --- Log Analytics Workspace ---
# Required by Container App Environment - this is where container
# stdout/stderr logs end up. Equivalent role to a CloudWatch Log Group.
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "PerGB2018"
  retention_in_days    = 30
}

# --- Container App Environment ---
# The secure boundary/network Container Apps run inside - conceptually
# similar to an ECS Cluster. You can run multiple Container Apps inside
# one environment; we only need one for now.
resource "azurerm_container_app_environment" "main" {
  name                       = "cae-${var.project_name}-${var.environment}"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
}

# --- User-Assigned Managed Identity ---
# We use a USER-assigned identity (created as its own independent
# resource) rather than a system-assigned one. Reason: a system-assigned
# identity doesn't exist until the Container App itself is created, but
# the role assignment below needs the identity's principal_id to exist
# BEFORE the Container App tries to pull an image with it - that's a
# circular dependency. A user-assigned identity has its own lifecycle, so
# we can grant it "AcrPull" first, then attach it to the Container App.
# This is the same reasoning as pre-creating an IAM role in AWS before
# attaching it to an ECS task definition.
resource "azurerm_user_assigned_identity" "main" {
  name                = "id-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

# --- Container App ---
# The actual running app - equivalent to an ECS Fargate Service/Task.
resource "azurerm_container_app" "main" {
  name                         = "ca-${var.project_name}-${var.environment}"
  resource_group_name          = azurerm_resource_group.main.name
  container_app_environment_id = azurerm_container_app_environment.main.id
  revision_mode                = "Single"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.main.id]
  }

  registry {
    server   = azurerm_container_registry.main.login_server
    identity = azurerm_user_assigned_identity.main.id
  }

  # Secrets defined here can be referenced by env vars below without their
  # values appearing directly in the container template. Note: this value
  # still ends up readable in Terraform state (state files are not
  # encrypted by default) - fine for a personal project, but in a real
  # team setting you'd pull this from Azure Key Vault instead. Worth
  # knowing as a limitation, not pretending it's fully secure.
  secret {
    name  = "nasa-api-key"
    value = var.nasa_api_key
  }

  template {
    container {
      name   = "asteroid-watch"
      image  = "${azurerm_container_registry.main.login_server}/asteroid-watch:${var.container_image_tag}"
      cpu    = 0.5
      memory = "1Gi"

      env {
        name        = "NASA_API_KEY"
        secret_name = "nasa-api-key"
      }
    }

    # Scale-to-zero: min_replicas = 0 means Azure stops billing compute
    # when nobody's using the app, and spins a replica back up on the next
    # request (with a short cold-start delay). This is the Container Apps
    # feature that doesn't really have a clean App Service equivalent -
    # closer to how Lambda/Fargate Spot behaves than a traditional web app.
    min_replicas = 0
    max_replicas = 2
  }

  ingress {
    external_enabled = true
    target_port       = 8000

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  # The registry pull needs the identity's role assignment to exist first,
  # or the first deployment can fail trying to pull the image before
  # permissions have propagated.
  depends_on = [azurerm_role_assignment.acr_pull]
}

# --- Role Assignment: let the identity (and therefore the Container App)
# pull from ACR ---
# Direct equivalent of an IAM policy granting an ECS task role
# `ecr:GetDownloadUrlForLayer` / `ecr:BatchGetImage` etc. "AcrPull" is a
# built-in Azure role scoped to exactly this one permission. Because this
# depends only on the user-assigned identity (not the Container App), it
# can be created first, breaking the circular dependency described above.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.main.principal_id
}
