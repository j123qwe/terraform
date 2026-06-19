# Vultr Compute Nodes — Terraform

Deploys **three Vultr compute instances** into a single region using the [Vultr Terraform provider](https://registry.terraform.io/providers/vultr/vultr/latest).

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.3.0
- A [Vultr API key](https://my.vultr.com/settings/#settingsapi) with full access
- (Optional) One or more SSH keys [uploaded to Vultr](https://my.vultr.com/settings/#settingssshkeys) — note their IDs

## Quick Start

```bash
# 1. Copy and populate the vars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set vultr_api_key and ssh_key_ids

# 2. Initialise providers
terraform init

# 3. Preview the plan
terraform plan

# 4. Apply
terraform apply
```

## Variables

| Variable | Default | Description |
|---|---|---|
| `vultr_api_key` | — | Vultr API key (sensitive) |
| `region` | `dfw` | Vultr region slug (Dallas) |
| `plan` | `vc2-4c-8gb` | Instance plan (4 vCPU / 8 GB) |
| `os_id` | `387` | OS ID (Ubuntu 22.04 LTS x64) |
| `node_count` | `3` | Number of nodes |
| `node_label_prefix` | `node` | Label prefix (`node-1`, `node-2`, …) |
| `hostname_prefix` | `node` | Hostname prefix |
| `ssh_key_ids` | `[]` | Vultr SSH key IDs to inject |
| `tags` | `[]` | Tags applied to each instance |
| `enable_private_network` | `true` | Enable private networking |
| `backups` | `disabled` | Managed backups (`enabled`/`disabled`) |

## Outputs

| Output | Description |
|---|---|
| `node_labels` | Label of each instance |
| `node_ids` | Vultr instance IDs |
| `node_public_ips` | Public IPv4 addresses |
| `node_private_ips` | Private IPv4 addresses |
| `node_ipv6` | IPv6 addresses |
| `node_status` | Power status of each node |

## Useful Vultr Region Slugs

| Slug | Location |
|---|---|
| `dfw` | Dallas, TX |
| `ewr` | New Jersey |
| `lax` | Los Angeles, CA |
| `atl` | Atlanta, GA |
| `sea` | Seattle, WA |
| `ams` | Amsterdam |
| `fra` | Frankfurt |
| `nrt` | Tokyo |

## Teardown

```bash
terraform destroy
```
