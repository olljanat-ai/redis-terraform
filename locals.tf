locals {
  # Only build a network when the caller did not bring their own.
  create_network = var.existing_network == null

  private_dns_zone_resource_id = local.create_network ? module.private_dns_zone[0].resource_id : var.existing_network.private_dns_zone_resource_id

  private_endpoint_subnet_resource_id = local.create_network ? module.virtual_network[0].subnets["private_endpoints"].resource_id : var.existing_network.private_endpoint_subnet_resource_id

  # Redis cache names are globally unique DNS labels, hence the random suffix on generated names.
  redis_names = {
    for key, cache in var.redis_caches :
    key => coalesce(cache.name, lower("redis-${var.workload}-${key}-${var.environment}-${random_string.suffix.result}"))
  }

  resource_group_name = coalesce(var.resource_group_name, "rg-${var.workload}-${var.environment}")

  tags = merge({
    environment = var.environment
    workload    = var.workload
    managed_by  = "terraform"
  }, var.tags)
}
