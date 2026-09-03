# redis-terraform

A minimal Terraform example that deploys a list of Redis services on Azure with
[Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/).

Everything lives in this single flat folder, and every cache is private, TLS-only and highly
available unless you explicitly ask for something else.

## Which Redis service

New deployments get **[Azure Managed Redis](https://learn.microsoft.com/en-us/azure/redis/overview)**
(`Microsoft.Cache/redisEnterprise`), the Redis Enterprise based successor to Azure Cache for Redis.
Set `legacy_redis = true` to deploy the classic **Azure Cache for Redis** (`Microsoft.Cache/Redis`)
instead.

|  | Azure Managed Redis (default) | Azure Cache for Redis (`legacy_redis = true`) |
| --- | --- | --- |
| Resource type | `Microsoft.Cache/redisEnterprise` | `Microsoft.Cache/Redis` |
| Sizing | `sku_name`, for example `Balanced_B10` | `sku_name` + `capacity`, for example `Premium` + `1` |
| Endpoint | `<cache>.<region>.redis.azure.net:10000` | `<cache>.redis.cache.windows.net:6380` |
| Privatelink zone | `privatelink.redis.azure.net` | `privatelink.redis.cache.windows.net` |
| Availability zones | Nodes spread over the zones of the region automatically | Zones listed explicitly, Premium only |
| Extras | Redis modules, `OSSCluster` policy | — |

The two are separate Azure resource types, so flipping `legacy_redis` on an existing deployment
replaces the caches and the private DNS zone rather than upgrading them in place. Migrate the data
yourself, for example with
[import/export](https://learn.microsoft.com/en-us/azure/redis/how-to-import-export-data).

## What it deploys

| Resource | Module |
| --- | --- |
| Resource group | [`Azure/avm-res-resources-resourcegroup/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm/0.4.0) `0.4.0` |
| Virtual network + private endpoint subnet | [`Azure/avm-res-network-virtualnetwork/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm/0.22.2) `0.22.2` |
| Privatelink zone + vnet link | [`Azure/avm-res-network-privatednszone/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-network-privatednszone/azurerm/0.5.0) `0.5.0` |
| One Azure Managed Redis instance per entry in `var.redis_caches` | [`Azure/avm-res-cache-redisenterprise/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-cache-redisenterprise/azurerm/0.2.0) `0.2.0` |
| One Azure Cache for Redis per entry in `var.redis_caches`, when `legacy_redis = true` | [`Azure/avm-res-cache-redis/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-cache-redis/azurerm/0.4.0) `0.4.0` |

The network is only created when `var.existing_network` is unset, so the same configuration works
both as a self-contained sandbox and against an existing hub-and-spoke network. Bring your own
network only works with the privatelink zone that matches the service in use — see the table above.

## Defaults

| Concern | Default | How to opt out |
| --- | --- | --- |
| Redis service | Azure Managed Redis | `legacy_redis = true` |
| Private networking | Private endpoint in the subnet above, DNS record in the private zone, no public listener | `private_endpoint_enabled = false` plus `public_network_access_enabled = true` |
| Encryption in transit | `minimum_tls_version = "1.2"`, plaintext disabled | `minimum_tls_version` (Azure Cache for Redis only) / `non_ssl_port_enabled = true` |
| High availability | Multiple nodes spread over availability zones | `high_availability = false` |

On Azure Managed Redis the service places the nodes of a highly available instance into separate
availability zones on its own, so `zones` stays empty unless you pin it. On Azure Cache for Redis the
zones have to be spelled out, they default to `["1", "2"]`, and Azure rejects a cache with more zones
than nodes — so `length(zones)` must stay `<= replica_count + 1`. For a three-zone cache there, set
`replica_count = 2` and `zones = ["1", "2", "3"]`.

## Usage

```bash
export ARM_SUBSCRIPTION_ID="<your subscription id>"
az login

terraform init
terraform plan  -var-file=prototype.tfvars
terraform apply -var-file=prototype.tfvars
```

`prototype.tfvars` is the variables file for the `prototype` environment and sits next to the
configuration. Copy it to add more environments.

## Adding a cache

`var.redis_caches` is a map so that each cache keeps a stable Terraform address; the map key is a
short logical name that ends up in the generated cache name. Names get a random suffix because Redis
names are DNS labels that have to be unique within their zone — set `name` explicitly to control it.

```hcl
redis_caches = {
  sessions = {}                                  # all defaults: private, TLS only, zone redundant
  search = {
    sku_name      = "MemoryOptimized_M20"
    redis_modules = [{ name = "RediSearch" }]
  }
}
```

Attributes that only apply to one of the two services are ignored by the other, so a cache that
stays on the shared attributes — `maxmemory_policy`, `high_availability`, `private_endpoint_enabled`,
`non_ssl_port_enabled`, `tags` — deploys either way. `maxmemory_policy` is always written in the
redis.conf spelling (`volatile-lru`) and translated to the Azure Managed Redis name (`VolatileLRU`).
`capacity`, `redis_version` and `replica_count` are Azure Cache for Redis only; `clustering_policy`
and `redis_modules` are Azure Managed Redis only.

## Connecting

`terraform output redis_caches` returns the hostname and port of each cache, plus the private
endpoint IP on Azure Cache for Redis. `ssl_port` is null on a cache that serves clients unencrypted
and `non_ssl_port` is null on a TLS-only one; Azure Managed Redis uses the single port 10000 for
both, Azure Cache for Redis uses 6380 for TLS and 6379 for plaintext.

Access keys are not exported on purpose. Read them with

```bash
az redisenterprise database list-keys --cluster-name <cache> --database-name default --resource-group <rg>
az redis list-keys --name <cache> --resource-group <rg>   # legacy_redis = true
```

or prefer Microsoft Entra authentication. Clients need to resolve the privatelink zone, so they have
to run inside the virtual network (or a network linked to that zone).

## Notes

- The AVM modules send anonymous usage telemetry. Set `enable_telemetry = false` to disable it.
- Provisioning takes a while: 20–30 minutes for a Premium Azure Cache for Redis, and longer when
  replicas are involved.
