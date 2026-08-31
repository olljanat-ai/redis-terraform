resource "random_string" "suffix" {
  length  = 5
  lower   = true
  numeric = true
  special = false
  upper   = false
}

module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  location         = var.location
  name             = local.resource_group_name
  enable_telemetry = var.enable_telemetry
  tags             = local.tags
}

module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  count = local.create_network ? 1 : 0

  location         = var.location
  parent_id        = module.resource_group.resource_id
  address_space    = [var.vnet_address_space]
  enable_telemetry = var.enable_telemetry
  name             = "vnet-${var.workload}-${var.environment}"
  subnets = {
    private_endpoints = {
      name             = "snet-private-endpoints"
      address_prefixes = [var.private_endpoint_subnet_address_prefix]
    }
  }
  tags = local.tags
}

# Without this zone the caches keep resolving to their public IP address.
module "private_dns_zone" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  count = local.create_network ? 1 : 0

  domain_name      = "privatelink.redis.cache.windows.net"
  parent_id        = module.resource_group.resource_id
  enable_telemetry = var.enable_telemetry
  tags             = local.tags
  virtual_network_links = {
    spoke = {
      name               = "vnl-${var.workload}-${var.environment}"
      virtual_network_id = module.virtual_network[0].resource_id
    }
  }
}

module "redis" {
  source  = "Azure/avm-res-cache-redis/azurerm"
  version = "0.4.0"

  for_each = var.redis_caches

  location            = var.location
  name                = local.redis_names[each.key]
  resource_group_name = module.resource_group.name
  capacity            = each.value.capacity
  enable_telemetry    = var.enable_telemetry

  # TLS only unless the cache explicitly asks for the plaintext port.
  enable_non_ssl_port = each.value.non_ssl_port_enabled
  minimum_tls_version = each.value.minimum_tls_version

  # High availability: replicas spread over availability zones.
  replicas_per_master = each.value.high_availability ? each.value.replica_count : null
  zones               = each.value.high_availability ? each.value.zones : []

  # Private by default: a private endpoint plus its DNS record, and no public listener.
  private_endpoints = each.value.private_endpoint_enabled ? {
    primary = {
      subnet_resource_id            = local.private_endpoint_subnet_resource_id
      private_dns_zone_resource_ids = [local.private_dns_zone_resource_id]
    }
  } : {}
  public_network_access_enabled = coalesce(each.value.public_network_access_enabled, !each.value.private_endpoint_enabled)

  redis_configuration = {
    maxmemory_policy = each.value.maxmemory_policy
  }
  redis_version = each.value.redis_version
  sku_name      = each.value.sku_name
  tags          = merge(local.tags, each.value.tags)
}
