variable "subscription_id" {
  type        = string
  default     = null
  description = "The Azure subscription to deploy into. Leave null to use the ARM_SUBSCRIPTION_ID environment variable."
}

variable "location" {
  type        = string
  default     = "swedencentral"
  description = "Azure region for every resource created by this example."
}

variable "environment" {
  type        = string
  default     = "prototype"
  description = "Environment name, used in generated resource names and tags."
}

variable "workload" {
  type        = string
  default     = "redis"
  description = "Short workload name, used in generated resource names and tags."
}

variable "legacy_redis" {
  type        = bool
  default     = false
  description = <<-DESCRIPTION
    Deploy the legacy Azure Cache for Redis (`Microsoft.Cache/Redis`) instead of Azure Managed Redis
    (`Microsoft.Cache/redisEnterprise`). Defaults to `false`, so new deployments get Azure Managed Redis.

    The two services are different Azure resource types with different SKUs, endpoints and privatelink
    zones, so flipping this on an existing deployment replaces the caches and the private DNS zone
    instead of upgrading them in place. Migrate the data yourself.

    Attributes of `var.redis_caches` that only apply to one of the services are ignored by the other;
    the description of that variable says which is which.
  DESCRIPTION
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "Name of the resource group to create. Defaults to rg-<workload>-<environment>."
}

variable "vnet_address_space" {
  type        = string
  default     = "10.60.0.0/22"
  description = "Address space of the virtual network created for the private endpoints. Ignored when var.existing_network is set."
}

variable "private_endpoint_subnet_address_prefix" {
  type        = string
  default     = "10.60.0.0/24"
  description = "Address prefix of the subnet that hosts the private endpoints. Ignored when var.existing_network is set."
}

variable "existing_network" {
  type = object({
    private_endpoint_subnet_resource_id = string
    private_dns_zone_resource_id        = string
  })
  default     = null
  description = <<-DESCRIPTION
    Bring your own network. When set, no virtual network, subnet or private DNS zone is created and the
    private endpoints are attached to the supplied resources instead.
    - `private_endpoint_subnet_resource_id` - Resource ID of the subnet hosting the private endpoints.
    - `private_dns_zone_resource_id` - Resource ID of an existing private DNS zone that is already linked
      to the network the clients resolve names from. The zone has to match the service in use:
      `privatelink.redis.azure.net` for Azure Managed Redis and `privatelink.redis.cache.windows.net`
      when `var.legacy_redis` is true.
  DESCRIPTION
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource, merged with the tags of the individual caches."
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Whether the Azure Verified Modules send their usage telemetry. See https://aka.ms/avm/telemetryinfo."
}

variable "redis_caches" {
  type = map(object({
    name                          = optional(string, null)
    sku_name                      = optional(string, null)
    high_availability             = optional(bool, true)
    zones                         = optional(list(string), null)
    private_endpoint_enabled      = optional(bool, true)
    public_network_access_enabled = optional(bool, null)
    minimum_tls_version           = optional(string, "1.2")
    non_ssl_port_enabled          = optional(bool, false)
    maxmemory_policy              = optional(string, "volatile-lru")
    tags                          = optional(map(string), {})

    # Azure Managed Redis only.
    clustering_policy = optional(string, "EnterpriseCluster")
    redis_modules = optional(list(object({
      name = string
      args = optional(string, null)
    })), [])

    # Azure Cache for Redis only (var.legacy_redis = true).
    capacity      = optional(number, 1)
    redis_version = optional(number, 6)
    replica_count = optional(number, 1)
  }))
  default     = {}
  description = <<-DESCRIPTION
    The Redis services to deploy. The map key is a short logical name that is used to build the cache name
    and to key the Terraform resources, so keep it stable.

    Every attribute is optional and defaults to a private, TLS-only, highly available cache:
    - `name` - Full name of the cache. Defaults to `redis-<workload>-<key>-<environment>-<random suffix>`
      because Redis names are DNS labels that have to be unique within their zone.
    - `sku_name` - Defaults to `Balanced_B0` for Azure Managed Redis and to `Premium` for Azure Cache for
      Redis. Azure Managed Redis SKUs are `<family>_<size>`, for example `Balanced_B10`,
      `MemoryOptimized_M20`, `ComputeOptimized_X10` or `FlashOptimized_A250`; Azure Cache for Redis
      accepts `Basic`, `Standard` or `Premium`.
    - `high_availability` - Replicate the cache over at least two nodes. Defaults to `true`.
    - `zones` - Availability zones to pin the nodes to. Defaults to `["1", "2"]` on Azure Cache for Redis,
      where the zones have to be spelled out, and to the region default on Azure Managed Redis, which
      spreads the nodes of a highly available instance over the zones of the region on its own.
    - `private_endpoint_enabled` - Create a private endpoint for the cache. Defaults to `true`.
    - `public_network_access_enabled` - Defaults to the inverse of `private_endpoint_enabled`, so a cache
      that is reachable over a private endpoint is not reachable from the internet.
    - `minimum_tls_version` - Defaults to `1.2`. Azure Managed Redis only supports `1.2`.
    - `non_ssl_port_enabled` - Serve clients unencrypted. Defaults to `false`. Azure Cache for Redis opens
      the extra plaintext port 6379 next to the TLS port 6380; Azure Managed Redis switches its single
      port 10000 from TLS to plaintext.
    - `maxmemory_policy` - Eviction policy in redis.conf spelling, one of `allkeys-lfu`, `allkeys-lru`,
      `allkeys-random`, `noeviction`, `volatile-lfu`, `volatile-lru`, `volatile-random` or `volatile-ttl`.
      Defaults to `volatile-lru`. Translated to the PascalCase name on Azure Managed Redis.
    - `tags` - Extra tags for this cache, merged on top of `var.tags`.

    Azure Managed Redis only, ignored when `var.legacy_redis` is true:
    - `clustering_policy` - `EnterpriseCluster` for a single endpoint with automatic sharding, or
      `OSSCluster` for the Redis Cluster API. Defaults to `EnterpriseCluster`.
    - `redis_modules` - Modules to load, for example `[{ name = "RedisJSON" }]`. Defaults to none.
      `RediSearch` requires the `EnterpriseCluster` policy.

    Azure Cache for Redis only, ignored unless `var.legacy_redis` is true:
    - `capacity` - Size of the cache within the SKU family (Premium: 1 = P1 / 6 GB). Defaults to `1`.
      Azure Managed Redis encodes the size in `sku_name` instead.
    - `redis_version` - Redis major version. Defaults to `6`.
    - `replica_count` - Replicas per primary when `high_availability` is enabled. Defaults to `1`. Azure
      rejects more zones than nodes, so `length(zones)` must stay `<= replica_count + 1`.
  DESCRIPTION

  validation {
    condition = alltrue([
      for v in var.redis_caches : v.sku_name == null || (var.legacy_redis
        ? contains(["Basic", "Standard", "Premium"], coalesce(v.sku_name, "Premium"))
        : can(regex("^(Balanced_B|ComputeOptimized_X|FlashOptimized_A|MemoryOptimized_M)[0-9]+$", coalesce(v.sku_name, "Balanced_B0")))
      )
    ])
    error_message = "sku_name must be one of Basic, Standard or Premium when legacy_redis is true, and an Azure Managed Redis SKU such as Balanced_B10, MemoryOptimized_M20, ComputeOptimized_X10 or FlashOptimized_A250 otherwise."
  }
  validation {
    condition     = !var.legacy_redis || alltrue([for v in var.redis_caches : coalesce(v.sku_name, "Premium") == "Premium" if v.high_availability])
    error_message = "high_availability on Azure Cache for Redis requires the Premium SKU, which is the only one supporting replicas and availability zones."
  }
  validation {
    condition     = !var.legacy_redis || alltrue([for v in var.redis_caches : length(coalesce(v.zones, ["1", "2"])) <= v.replica_count + 1 if v.high_availability])
    error_message = "zones must not contain more entries than the cache has nodes (replica_count + 1)."
  }
  validation {
    condition = alltrue([
      for v in var.redis_caches : contains(var.legacy_redis ? ["1.0", "1.1", "1.2"] : ["1.2"], v.minimum_tls_version)
    ])
    error_message = "minimum_tls_version must be 1.2, or one of 1.0, 1.1 or 1.2 when legacy_redis is true."
  }
  validation {
    condition     = alltrue([for v in var.redis_caches : !(v.private_endpoint_enabled == false && v.public_network_access_enabled == false)])
    error_message = "A cache with neither a private endpoint nor public network access would be unreachable."
  }
  validation {
    condition = alltrue([
      for v in var.redis_caches : contains(
        ["allkeys-lfu", "allkeys-lru", "allkeys-random", "noeviction", "volatile-lfu", "volatile-lru", "volatile-random", "volatile-ttl"],
        v.maxmemory_policy
      )
    ])
    error_message = "maxmemory_policy must be one of allkeys-lfu, allkeys-lru, allkeys-random, noeviction, volatile-lfu, volatile-lru, volatile-random or volatile-ttl."
  }
  validation {
    condition     = var.legacy_redis || alltrue([for v in var.redis_caches : contains(["EnterpriseCluster", "OSSCluster"], v.clustering_policy)])
    error_message = "clustering_policy must be either EnterpriseCluster or OSSCluster."
  }
  validation {
    condition     = var.legacy_redis || alltrue([for v in var.redis_caches : alltrue([for m in v.redis_modules : contains(["RediSearch", "RedisJSON", "RedisBloom", "RedisTimeSeries"], m.name)])])
    error_message = "redis_modules may only contain RediSearch, RedisJSON, RedisBloom or RedisTimeSeries."
  }
  validation {
    condition     = !var.legacy_redis || alltrue([for v in var.redis_caches : length(v.redis_modules) == 0])
    error_message = "redis_modules are an Azure Managed Redis feature and cannot be used when legacy_redis is true."
  }
}
