# Linode Compute Nodes — Terraform

Deploys **three Linode compute instances** into a single region using the [Linode Terraform provider](https://registry.terraform.io/providers/linode/linode/latest).

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.3.0
- A [Linode API token](https://cloud.linode.com/profile/tokens) with **Read/Write** access to Linodes

## Quick Start

```bash
# 1. Copy and populate the vars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set linode_token, root_pass, ssh_authorized_keys

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
| `linode_token` | — | Linode API token (sensitive) |
| `region` | `us-central` | Linode region |
| `instance_type` | `g6-standard-4` | Instance plan (4 vCPU / 8 GB) |
| `image` | `linode/ubuntu22.04` | OS image |
| `node_count` | `3` | Number of nodes |
| `node_label_prefix` | `node` | Label prefix (`node-1`, `node-2`, …) |
| `root_pass` | — | Root password (sensitive) |
| `ssh_authorized_keys` | `[]` | SSH public keys to inject |
| `tags` | `[]` | Tags applied to each instance |
| `private_ip` | `true` | Enable private networking |
| `backups_enabled` | `false` | Enable Linode managed backups |

## Outputs

| Output | Description |
|---|---|
| `node_labels` | Label of each instance |
| `node_ids` | Linode instance IDs |
| `node_public_ips` | Public IPv4 addresses |
| `node_private_ips` | Private IPv4 addresses |
| `node_ipv6` | IPv6 addresses |

## Teardown

```bash
terraform destroy
```
