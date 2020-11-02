# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY A VAULT CLUSTER IN AZURE
# These configurations show an example of how to use the consul-cluster module to deploy Consul in Azure. We deploy two
# Scale Sets: one with Consul server nodes and one with Consul client nodes. Note that these templates assume
# that the Custom Image you provide via the image_id input variable is built from the
# examples/consul-image/consul.json Packer template.
# ---------------------------------------------------------------------------------------------------------------------

provider "azurerm" {
  version   = "~>2.11.0"
  features  {}

  skip_provider_registration  = true
}

resource "random_password" "default_password" {
  length            = 32
  special           = true
  override_special  = "_%@"
}

resource "random_id" "random" {
  byte_length = 4
}

data "azurerm_image" "vault_image" {
  name                = var.image_name
  resource_group_name = var.image_rg_name
}

data "azurerm_storage_account" "state" {
  name                  = var.state_storage_name
  resource_group_name   = var.state_rg_name
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE NECESSARY NETWORK RESOURCES FOR THE EXAMPLE
# ---------------------------------------------------------------------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name      = var.resource_group_name
  location  = var.location
}

resource "azurerm_virtual_network" "consul" {
  name = "consul-vnet"
  address_space = [var.address_space]
  location = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "consul" {
  name = "consul-subnet"
  resource_group_name = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.consul.name
  address_prefixes = [var.consul_subnet_address]
}

# resource "azurerm_subnet" "vault" {
#   name = "vault-subnet"
#   resource_group_name = azurerm_resource_group.rg.name
#   virtual_network_name = azurerm_virtual_network.consul.name
#   address_prefixes = [var.vault_subnet_address]
# }

resource "azurerm_subnet_network_security_group_association" "consul" {
  subnet_id                 = azurerm_subnet.consul.id
  network_security_group_id = module.consul_servers.consul_nsg
}

# resource "azurerm_subnet_network_security_group_association" "vault" {
#   subnet_id                 = azurerm_subnet.vault.id
#   network_security_group_id = module.vault_servers.vault_nsg
# }

resource "azurerm_storage_account" "consul_storage" {
  name                = lower(random_id.random.hex)
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  
  account_tier                = "Standard"
  account_replication_type    = "LRS"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE CONSUL SERVER NODES
# ---------------------------------------------------------------------------------------------------------------------

module "consul_servers" {
  source = "./modules/consul-cluster" #"git::git@github.com:hashicorp/terraform-azurerm-consul.git//modules/consul-cluster?ref=v0.0.5"

  cluster_name      = var.consul_cluster_name
  cluster_size      = var.num_consul_servers
  key_data          = var.key_data
  default_password  = random_password.default_password.result

  resource_group_name = azurerm_resource_group.rg.name
  storage_account_name = azurerm_storage_account.consul_storage.name

  location = azurerm_resource_group.rg.location
  custom_data = data.template_file.custom_data_consul.rendered
  instance_size = var.instance_size
  image_id = data.azurerm_image.vault_image.id
  subnet_id = azurerm_subnet.consul.id
  allowed_inbound_cidr_blocks = var.allowed_inbound_cidr_blocks
  allowed_ssh_cidr_blocks = ["66.169.180.119"]
}

# ---------------------------------------------------------------------------------------------------------------------
# THE CUSTOM DATA SCRIPT THAT WILL RUN ON EACH CONSUL SERVER AZURE INSTANCE WHEN IT'S BOOTING
# This script will configure and start Consul
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "custom_data_consul" {
  template = file("${path.module}/custom-data-consul.sh")

  vars = {
    scale_set_name = var.consul_cluster_name
    subscription_id = var.subscription_id
    tenant_id = var.tenant_id
    client_id = var.client_id
    secret_access_key = var.secret_access_key
  }
}

# ---------------------------------------------------------------------------------------------------------------------
# CREATE THE STORAGE
# ---------------------------------------------------------------------------------------------------------------------
# resource "azurerm_storage_container" "vault_storage" {
#   name                  = "vault"
#   storage_account_name  = azurerm_storage_account.consul_storage.name
#   container_access_type = "private"
# }

# ---------------------------------------------------------------------------------------------------------------------
# DEPLOY THE VAULT SERVER NODES
# ---------------------------------------------------------------------------------------------------------------------

module "vault_servers" {
  # When using these modules in your own templates, you will need to use a Git URL with a ref attribute that pins you
  # to a specific version of the modules, such as the following example:
  # source = "git::git@github.com:hashicorp/terraform-azurerm-vault.git//modules/vault-cluster?ref=v0.0.1"
  source = "./modules/vault-cluster"

  cluster_name      = var.vault_cluster_name
  cluster_size      = var.num_vault_servers
  key_data          = var.key_data
  default_password  = random_password.default_password.result

  resource_group_name = azurerm_resource_group.rg.name
  storage_account_name = azurerm_storage_account.consul_storage.name

  location = azurerm_resource_group.rg.location
  custom_data = data.template_file.custom_data_vault.rendered
  instance_size = var.instance_size
  image_id = data.azurerm_image.vault_image.id
  subnet_id = azurerm_subnet.consul.id
  consul_subnet = var.consul_subnet_address
  storage_container_name = "vault"
  associate_public_ip_address_load_balancer = true
  allowed_ssh_cidr_blocks = ["66.169.180.119"]
}

# ---------------------------------------------------------------------------------------------------------------------
# THE CUSTOM DATA SCRIPT THAT WILL RUN ON EACH CONSUL SERVER AZURE INSTANCE WHEN IT'S BOOTING
# This script will configure and start Consul
# ---------------------------------------------------------------------------------------------------------------------
data "template_file" "custom_data_vault" {
  template = file("${path.module}/custom-data-vault.sh")

  vars = {
    scale_set_name = var.consul_cluster_name
    subscription_id = var.subscription_id
    tenant_id = var.tenant_id
    client_id = var.client_id
    secret_access_key = var.secret_access_key
    azure_account_name = azurerm_storage_account.consul_storage.name
    azure_account_key = azurerm_storage_account.consul_storage.primary_access_key
    azure_container = module.vault_servers.storage_containter_id
  }
}
