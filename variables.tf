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
    - `private_dns_zone_resource_id` - Resource ID of an existing `privatelink.redis.cache.windows.net` zone
      that is already linked to the network the clients resolve names from.
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
    sku_name                      = optional(string, "Premium")
    capacity                      = optional(number, 1)
    redis_version                 = optional(number, 6)
    high_availability             = optional(bool, true)
    replica_count                 = optional(number, 1)
    zones                         = optional(list(string), ["1", "2"])
    private_endpoint_enabled      = optional(bool, true)
    public_network_access_enabled = optional(bool, null)
    minimum_tls_version           = optional(string, "1.2")
    non_ssl_port_enabled          = optional(bool, false)
    maxmemory_policy              = optional(string, "volatile-lru")
    tags                          = optional(map(string), {})
  }))
  default     = {}
  description = <<-DESCRIPTION
    The Redis services to deploy. The map key is a short logical name that is used to build the cache name
    and to key the Terraform resources, so keep it stable.

    Every attribute is optional and defaults to a private, TLS-only, highly available cache:
    - `name` - Full name of the cache. Defaults to `redis-<workload>-<key>-<environment>-<random suffix>`
      because Redis cache names have to be globally unique.
    - `sku_name` - `Basic`, `Standard` or `Premium`. Defaults to `Premium`, which is required for zone redundancy.
    - `capacity` - Size of the cache within the SKU family (Premium: 1 = P1 / 6 GB). Defaults to `1`.
    - `redis_version` - Redis major version. Defaults to `6`.
    - `high_availability` - Deploy replicas across availability zones. Defaults to `true`.
    - `replica_count` - Replicas per primary when `high_availability` is enabled. Defaults to `1`.
    - `zones` - Availability zones to spread the nodes over. Defaults to `["1", "2"]`. Azure rejects more
      zones than nodes, so the list must not be longer than `replica_count + 1`.
    - `private_endpoint_enabled` - Create a private endpoint for the cache. Defaults to `true`.
    - `public_network_access_enabled` - Defaults to the inverse of `private_endpoint_enabled`, so a cache
      that is reachable over a private endpoint is not reachable from the internet.
    - `minimum_tls_version` - Defaults to `1.2`.
    - `non_ssl_port_enabled` - Expose the unencrypted port 6379. Defaults to `false`, so only TLS on 6380.
    - `maxmemory_policy` - Eviction policy. Defaults to `volatile-lru`.
    - `tags` - Extra tags for this cache, merged on top of `var.tags`.
  DESCRIPTION

  validation {
    condition     = alltrue([for v in var.redis_caches : contains(["Basic", "Standard", "Premium"], v.sku_name)])
    error_message = "sku_name must be one of Basic, Standard or Premium."
  }
  validation {
    condition     = alltrue([for v in var.redis_caches : v.sku_name == "Premium" if v.high_availability])
    error_message = "high_availability requires the Premium SKU, which is the only one supporting replicas and availability zones."
  }
  validation {
    condition     = alltrue([for v in var.redis_caches : length(v.zones) <= v.replica_count + 1 if v.high_availability])
    error_message = "zones must not contain more entries than the cache has nodes (replica_count + 1)."
  }
  validation {
    condition     = alltrue([for v in var.redis_caches : contains(["1.0", "1.1", "1.2"], v.minimum_tls_version)])
    error_message = "minimum_tls_version must be one of 1.0, 1.1 or 1.2."
  }
  validation {
    condition     = alltrue([for v in var.redis_caches : !(v.private_endpoint_enabled == false && v.public_network_access_enabled == false)])
    error_message = "A cache with neither a private endpoint nor public network access would be unreachable."
  }
}
