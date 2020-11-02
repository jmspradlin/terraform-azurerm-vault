#---------------------------------------------------------------------------------------------------------------------
# CREATE STORAGE BUCKET
# ---------------------------------------------------------------------------------------------------------------------
resource "azurerm_storage_container" "vault" {
  name                  = var.storage_container_name
  storage_account_name  = var.storage_account_name
  container_access_type = "private"
}


#---------------------------------------------------------------------------------------------------------------------
# CREATE A VIRTUAL MACHINE SCALE SET TO RUN VAULT
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_virtual_machine_scale_set" "vault" {
  count = var.associate_public_ip_address_load_balancer ? 0 : 1
  name = var.cluster_name
  location = var.location
  resource_group_name = var.resource_group_name
  upgrade_policy_mode = "Manual"

  sku {
    name = var.instance_size
    tier = var.instance_tier
    capacity = var.cluster_size
  }

  os_profile {
    computer_name_prefix = var.vault_computer_name_prefix
    admin_username = var.vault_admin_user_name

    #This password is unimportant as it is disabled below in the os_profile_linux_config
    admin_password = var.default_password
    custom_data = var.custom_data
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path = "/home/${var.vault_admin_user_name}/.ssh/authorized_keys"
      key_data = file(var.key_data)
    }
  }

  network_profile {
    name = "VaultNetworkProfile"
    primary = true

    ip_configuration {
      name = "VaultIPConfiguration"
      primary = true
      subnet_id = var.subnet_id
    }
  }

  storage_profile_image_reference {
    id = var.image_id
  }

  storage_profile_os_disk {
    name = ""
    caching = "ReadWrite"
    create_option = "FromImage"
    os_type = "Linux"
    managed_disk_type = "Standard_LRS"
  }

  tags = {
    scaleSetName = var.cluster_name
  }
}

#---------------------------------------------------------------------------------------------------------------------
# CREATE A VIRTUAL MACHINE SCALE SET TO RUN VAULT
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_virtual_machine_scale_set" "vault" {
  name = var.cluster_name
  location = var.location
  resource_group_name = var.resource_group_name
  upgrade_policy_mode = "Manual"

  sku {
    name = var.instance_size
    tier = var.instance_tier
    capacity = var.cluster_size
  }

  os_profile {
    computer_name_prefix = var.vault_computer_name_prefix
    admin_username = var.vault_admin_user_name

    #This password is unimportant as it is disabled below in the os_profile_linux_config
    admin_password = var.default_password
    custom_data = var.custom_data
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path = "/home/${var.vault_admin_user_name}/.ssh/authorized_keys"
      key_data = file(var.key_data)
    }
  }

  network_profile {
    name = "VaultNetworkProfile"
    primary = true

    ip_configuration {
      name = "VaultIPConfiguration"
      primary = true
      subnet_id = var.subnet_id
      # load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.vault_bepool[count.index].id]
      # load_balancer_inbound_nat_rules_ids = [element(azurerm_lb_nat_pool.vault_lbnatpool.*.id, count.index)]
    }
  }

  storage_profile_image_reference {
    id = var.image_id
  }

  storage_profile_os_disk {
    name = ""
    caching = "ReadWrite"
    create_option = "FromImage"
    os_type = "Linux"
    managed_disk_type = "Standard_LRS"
  }

  tags = {
    scaleSetName = var.cluster_name
  }
}

#---------------------------------------------------------------------------------------------------------------------
# CREATE A SECURITY GROUP AND RULES FOR SSH
# ---------------------------------------------------------------------------------------------------------------------

resource "azurerm_network_security_group" "vault" {
  name = var.cluster_name
  location = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_network_security_rule" "ssh" {
  count = length(var.allowed_ssh_cidr_blocks)

  access = "Allow"
  destination_address_prefix = "*"
  destination_port_range = "22"
  direction = "Inbound"
  name = "SSH${count.index + 10}"
  network_security_group_name = azurerm_network_security_group.vault.name
  priority = 200 + count.index
  protocol = "Tcp"
  resource_group_name = var.resource_group_name
  source_address_prefix = element(var.allowed_ssh_cidr_blocks, count.index)
  source_port_range = "1024-65535"
}

# resource "azurerm_network_security_rule" "consul_inbound" {
#   access = "Allow"
#   destination_address_prefix = "*"
#   destination_port_range = "*"
#   direction = "Inbound"

#   name  = "consul_inbound"
#   network_security_group_name = azurerm_network_security_group.vault.name

#   priority                    = 211
#   protocol                    = "Tcp"
#   resource_group_name         = var.resource_group_name
#   source_address_prefix       = var.consul_subnet
#   source_port_range           = "1024-65535"
# }

# resource "azurerm_network_security_rule" "consul_outbound" {
#   access = "Allow"
#   destination_address_prefix = var.consul_subnet
#   destination_port_range = "*"
#   direction = "Outbound"

#   name  = "consul_outbound"
#   network_security_group_name = azurerm_network_security_group.vault.name

#   priority                    = 212
#   protocol                    = "Tcp"
#   resource_group_name         = var.resource_group_name
#   source_address_prefix     = "*"
#   source_port_range           = "*"
# }