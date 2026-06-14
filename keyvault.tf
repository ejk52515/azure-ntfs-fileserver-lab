# Look up details about the identity currently logged into az CLI (you)
data "azurerm_client_config" "current" {}

# random_id — generates an 8-char hex suffix for a globally-unique vault name
resource "random_id" "kv_suffix" {
  byte_length = 4
}

# The Key Vault itself
resource "azurerm_key_vault" "lab_kv" {
  name                       = "kv-fslab-${random_id.kv_suffix.hex}"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags = {
    Environment = "Lab"
    ManagedBy   = "Terraform"
  }
}

# Grant the logged-in user permission to write secrets into the vault
resource "azurerm_role_assignment" "kv_deployer_access" {
  scope                = azurerm_key_vault.lab_kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Store the admin password as a secret inside the vault
resource "azurerm_key_vault_secret" "admin_password" {
  name         = "vm-admin-password"
  value        = var.admin_password
  key_vault_id = azurerm_key_vault.lab_kv.id
  depends_on   = [azurerm_role_assignment.kv_deployer_access]
  tags = {
    ManagedBy = "Terraform"
  }
}