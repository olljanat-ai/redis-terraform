# redis-terraform

A minimal Terraform example that deploys a list of Azure Cache for Redis services with
[Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/).

Everything lives in this single flat folder, and every cache is private, TLS-only and highly
available unless you explicitly ask for something else.

## What it deploys

| Resource | Module |
| --- | --- |
| Resource group | [`Azure/avm-res-resources-resourcegroup/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-resources-resourcegroup/azurerm/0.4.0) `0.4.0` |
| Virtual network + private endpoint subnet | [`Azure/avm-res-network-virtualnetwork/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm/0.22.2) `0.22.2` |
| `privatelink.redis.cache.windows.net` zone + vnet link | [`Azure/avm-res-network-privatednszone/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-network-privatednszone/azurerm/0.5.0) `0.5.0` |
| One Redis cache per entry in `var.redis_caches` | [`Azure/avm-res-cache-redis/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-cache-redis/azurerm/0.4.0) `0.4.0` |

The network is only created when `var.existing_network` is unset, so the same configuration works
both as a self-contained sandbox and against an existing hub-and-spoke network.

## Defaults

| Concern | Default | How to opt out |
| --- | --- | --- |
| Private networking | Private endpoint in the subnet above, DNS record in the private zone, `public_network_access_enabled = false` | `private_endpoint_enabled = false` plus `public_network_access_enabled = true` |
| Encryption in transit | `minimum_tls_version = "1.2"`, plaintext port 6379 disabled | `minimum_tls_version` / `non_ssl_port_enabled = true` |
| High availability | Premium SKU with one replica per primary spread over zones `["1", "2"]` | `high_availability = false` |

Azure rejects a cache with more zones than nodes, so `length(zones)` must stay `<= replica_count + 1`.
For a three-zone cache, set `replica_count = 2` and `zones = ["1", "2", "3"]`.

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
short logical name that ends up in the generated cache name. Names get a random suffix because
Redis cache names are globally unique DNS labels — set `name` explicitly to control it.

```hcl
redis_caches = {
  sessions = {}                              # all defaults: private, TLS only, zone redundant
  search   = { capacity = 2, replica_count = 2, zones = ["1", "2", "3"] }
}
```

## Connecting

`terraform output redis_caches` returns the hostname, TLS port and private endpoint IP of each
cache. Access keys are not exported on purpose; read them with
`az redis list-keys --name <cache> --resource-group <rg>`, or prefer Microsoft Entra
authentication. Clients need to resolve the private DNS zone, so they have to run inside the
virtual network (or a network linked to that zone).

## Notes

- The AVM modules send anonymous usage telemetry. Set `enable_telemetry = false` to disable it.
- Premium caches take 20–30 minutes to provision, and longer when replicas are involved.
