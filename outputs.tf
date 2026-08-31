output "private_dns_zone_resource_id" {
  description = "Resource ID of the privatelink.redis.cache.windows.net zone the caches are registered in."
  value       = local.private_dns_zone_resource_id
}

output "private_endpoint_subnet_resource_id" {
  description = "Resource ID of the subnet hosting the private endpoints."
  value       = local.private_endpoint_subnet_resource_id
}

output "redis_caches" {
  description = <<-DESCRIPTION
    Connection details per cache, keyed the same way as var.redis_caches. Access keys are deliberately not
    exported; read them with `az redis list-keys` or use Microsoft Entra authentication instead.
  DESCRIPTION
  value = {
    for key, cache in module.redis : key => {
      name                      = cache.name
      resource_id               = cache.resource_id
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
