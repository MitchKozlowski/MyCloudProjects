# Outputs - values Terraform prints after apply, and that you can query
# later with `terraform output`. Useful for grabbing values you need for
# other commands (like the ACR login server for `docker push`) without
# having to go look them up in the Azure Portal.

output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "acr_login_server" {
  description = "Use this as the registry host when tagging/pushing images"
  value       = azurerm_container_registry.main.login_server
}

output "container_app_url" {
  description = "Public URL of the deployed app"
  value       = "https://${azurerm_container_app.main.ingress[0].fqdn}"
}
