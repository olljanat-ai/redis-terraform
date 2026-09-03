locals {
  # Azure Managed Redis (Microsoft.Cache/redisEnterprise) is the default. var.legacy_redis switches the
  # whole deployment back to Azure Cache for Redis (Microsoft.Cache/Redis).
  managed_redis = !var.legacy_redis

  # Azure Managed Redis spells the eviction policy in PascalCase while Azure Cache for Redis uses the
  # redis.conf style. Callers configure the redis.conf style so the same tfvars work in both modes.
  eviction_policies = {
    "allkeys-lfu"     = "AllKeysLFU"
    "allkeys-lru"     = "AllKeysLRU"
    "allkeys-random"  = "AllKeysRandom"
    "noeviction"      = "NoEviction"
    "volatile-lfu"    = "VolatileLFU"
    "volatile-lru"    = "VolatileLRU"
    "volatile-random" = "VolatileRandom"
    "volatile-ttl"    = "VolatileTTL"
  }

  # Only build a network when the caller did not bring their own.
  create_network = var.existing_network == null

  # The two services resolve through different privatelink zones.
  private_dns_zone_name = local.managed_redis ? "privatelink.redis.azure.net" : "privatelink.redis.cache.windows.net"

  private_dns_zone_resource_id = local.create_network ? module.private_dns_zone[0].resource_id : var.existing_network.private_dns_zone_resource_id

  private_endpoint_subnet_resource_id = local.create_network ? module.virtual_network[0].subnets["private_endpoints"].resource_id : var.existing_network.private_endpoint_subnet_resource_id

  # Redis names are DNS labels that have to be unique within their zone, hence the random suffix on
  # generated names.
  redis_names = {
    for key, cache in var.redis_caches :
    key => coalesce(cache.name, lower("redis-${var.workload}-${key}-${var.environment}-${random_string.suffix.result}"))
  }

  # Settings whose default depends on the service, resolved once so main.tf and outputs.tf agree.
  redis_settings = {
    for key, cache in var.redis_caches : key => {
      # Azure Managed Redis encodes size in the SKU, Azure Cache for Redis in sku_name + capacity.
      sku_name = coalesce(cache.sku_name, local.managed_redis ? "Balanced_B0" : "Premium")

      # Azure Cache for Redis needs the zones spelled out. Azure Managed Redis spreads the nodes of a
      # highly available instance over the zones of the region on its own, so the list stays empty
      # unless the caller pins it.
      zones = !cache.high_availability ? [] : (
        cache.zones != null ? cache.zones : (local.managed_redis ? [] : ["1", "2"])
      )

      public_network_access_enabled = coalesce(cache.public_network_access_enabled, !cache.private_endpoint_enabled)
    }
  }

  resource_group_name = coalesce(var.resource_group_name, "rg-${var.workload}-${var.environment}")

  tags = merge({
    environment = var.environment
    workload    = var.workload
    managed_by  = "terraform"
  }, var.tags)
}
