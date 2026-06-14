output "dc01_public_ip" {
  value       = azurerm_public_ip.dc01.ip_address
  description = "DC01 public IP."
}
output "dc01_private_ip" {
  value       = azurerm_network_interface.dc01.private_ip_address
  description = "Always 10.0.1.4 — DC01 static DNS address."
}
output "fs01_public_ip" {
  value       = azurerm_public_ip.fs01.ip_address
  description = "FS01 public IP."
}
output "client01_public_ip" {
  value       = azurerm_public_ip.client01.ip_address
  description = "RDP here as test users to verify the lab."
}
output "key_vault_name" {
  value       = azurerm_key_vault.lab_kv.name
  description = "Pass to configure-lab.ps1 with -KeyVaultName."
}