# Variables for the "prototype" environment.
#   terraform apply -var-file=prototype.tfvars

location    = "swedencentral"
environment = "prototype"
workload    = "redis"

# Deploy Azure Managed Redis. Set to true to fall back to the legacy Azure Cache for Redis instead --
# a different resource type, so switching replaces the caches rather than upgrading them.
legacy_redis = false

vnet_address_space                     = "10.60.0.0/22"
private_endpoint_subnet_address_prefix = "10.60.0.0/24"

tags = {
  cost_center = "prototype"
  owner       = "platform-team"
}

# Every cache below inherits the secure defaults: private endpoint only, TLS 1.2 minimum, no plaintext
# port, and a highly available instance spread over availability zones. Nothing here is specific to one
# of the two services, so the same caches deploy either way.
redis_caches = {
  sessions = {
    maxmemory_policy = "volatile-lru"
  }

  cart = {
    maxmemory_policy = "allkeys-lru"
    tags = {
      component = "checkout"
    }
  }

  ratelimit = {
    maxmemory_policy = "allkeys-lru"
  }

  # Opting out has to be explicit. Uncomment for a cheap, publicly reachable cache without replicas --
  # it gives up both the private endpoint and the high availability guarantee. The SKU is per service,
  # so use "Basic" instead of "Balanced_B0" when legacy_redis is true.
  # scratch = {
  #   sku_name                      = "Balanced_B0"
  #   high_availability             = false
  #   private_endpoint_enabled      = false
  #   public_network_access_enabled = true
  # }
}
