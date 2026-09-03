output "private_dns_zone_name" {
  description = "Name of the privatelink zone the caches are registered in. Differs per service."
  value       = local.private_dns_zone_name
}

output "private_dns_zone_resource_id" {
  description = "Resource ID of the privatelink zone the caches are registered in."
  value       = local.private_dns_zone_resource_id
}

output "private_endpoint_subnet_resource_id" {
  description = "Resource ID of the subnet hosting the private endpoints."
  value       = local.private_endpoint_subnet_resource_id
}

output "redis_service" {
  description = "The Azure service the caches were deployed with."
  value       = local.managed_redis ? "Azure Managed Redis" : "Azure Cache for Redis"
}

output "redis_caches" {
  description = <<-DESCRIPTION
    Connection details per cache, keyed the same way as var.redis_caches. `ssl_port` is null on a cache
    that serves clients unencrypted, `non_ssl_port` is null on a TLS-only one. `private_endpoint_ip` is
    only reported for Azure Cache for Redis; the Azure Managed Redis module does not export it, so read
    it from the private endpoint's network interface when you need it.

    Access keys are deliberately not exported; read them with `az redisenterprise database list-keys
    --cluster-name <cache> --database-name default --resource-group <rg>` (`az redis list-keys --name
    <cache> --resource-group <rg>` when var.legacy_redis is true), or use Microsoft Entra authentication
    instead.
  DESCRIPTION
  value = local.managed_redis ? {
    for key, cache in module.managed_redis : key => {
      name                      = cache.name
      resource_id               = cache.resource_id
      sku_name                  = local.redis_settings[key].sku_name
      hostname                  = cache.hostname
      ssl_port                  = var.redis_caches[key].non_ssl_port_enabled ? null : 10000
      non_ssl_port              = var.redis_caches[key].non_ssl_port_enabled ? 10000 : null
      private_endpoint_ip       = null
      private_endpoint_enabled  = var.redis_caches[key].private_endpoint_enabled
      high_availability_enabled = var.redis_caches[key].high_availability
    }
    } : {
    for key, cache in module.redis : key => {
      name                      = cache.name
      resource_id               = cache.resource_id
      sku_name                  = local.redis_settings[key].sku_name
      hostname                  = "${cache.name}.redis.cache.windows.net"
      ssl_port                  = 6380
      non_ssl_port              = var.redis_caches[key].non_ssl_port_enabled ? 6379 : null
      private_endpoint_ip       = try(cache.private_endpoints["primary"].private_service_connection[0].private_ip_address, null)
      private_endpoint_enabled  = var.redis_caches[key].private_endpoint_enabled
      high_availability_enabled = var.redis_caches[key].high_availability
    }
  }
}

output "resource_group_name" {
  description = "Name of the resource group holding the caches."
  value       = module.resource_group.name
}

output "virtual_network_resource_id" {
  description = "Resource ID of the virtual network created by this example, or null when an existing network is used."
  value       = local.create_network ? module.virtual_network[0].resource_id : null
}
