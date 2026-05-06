# Harvester Lab Cluster Factory (Terraform)

This project provisions repeatable Kubernetes lab clusters on Harvester with:

- 3 control-plane VMs (configurable)
- 3 worker VMs (configurable)
- 1 HAProxy VM
- Dual-NIC static networking via cloud-init/netplan
- Automatic HAProxy configuration for Kubernetes control-plane TCP ports 6443 and 9345

Designed for technical engineers who need to create and destroy clusters repeatedly.

## What Gets Built

- Namespace in Harvester/Kubernetes from `var.namespace`
- Master VMs from `harvester_virtualmachine.masters`
- Worker VMs from `harvester_virtualmachine.workers`
- HAProxy VM from `harvester_virtualmachine.haproxy`

Network model per VM:

- NIC1 on VLAN0 (static IP, route/default gateway, DNS)
- NIC2 on VLAN111 (static IP)

Disk model:

- `disk0` default 50Gi for master
- `disk0` default 100Gi for workers

## Repository Layout

- `main.tf`: namespace + VM resources + cloud-init network/user setup
- `variables.tf`: full variable contract
- `provders.tf`: provider declarations (Harvester, Kubernetes)
- `terraform.tfvars.example`: example values

## Prerequisites

1. Terraform installed (1.5+ recommended)
2. Valid Harvester kubeconfig at `~/.kube/config`
3. Harvester image available for `image_id` (cloud image recommended)
4. Harvester networks available:
   - VLAN0 network referenced by `nic1_network_name`
   - VLAN111 network referenced by `nic2_network_name`
5. SSH keypair available locally
6. Public key value ready for `vm_ssh_public_key`

## Quick Start

1. Initialize providers:

   terraform init

2. Create environment values:

   cp terraform.tfvars.example terraform.tfvars

3. Edit `terraform.tfvars` for your lab:

- Required at minimum:
  - `namespace`
  - `image_id`
  - `vm_username`
  - `vm_ssh_public_key`
  - NIC CIDRs, gateway, and DNS
- Strongly recommended for repeated labs:
  - `mac_seed` unique per cluster (prevents MAC collisions)

4. Validate:

   terraform validate

5. Launch VMs:

   terraform apply

## Repeatable Cluster Lifecycle (Create/Destroy Loop)

### Create a New Cluster Iteration

1. Set unique values in `terraform.tfvars`:
   - `namespace`
   - `mac_seed`
   - VM hostnames/IPs if needed
2. Run:

   terraform apply

### Destroy the Cluster

Run:

   terraform destroy

### Build Again

Update `namespace` and `mac_seed`, then:

   terraform apply

Using a fresh namespace and seed each run avoids stale object collisions and MAC reuse.

## Troubleshooting

### Static networking not applied on existing VMs

Cloud-init network changes are first-boot sensitive. Recreate VMs when changing network cloud-init behavior.

### VM connectivity issues

- Verify VLAN0 reachability from your workstation to all node NIC1 addresses
- Verify `vm_username` matches image user
- Verify private key path and public key pairing

## State and Team Usage Notes

This project currently uses local state. For multi-user or CI-driven labs, use a remote backend (for example S3-compatible object storage with locking) before team-scale use.

## Git Hygiene

The included `.gitignore` excludes state files, tfvars, local artifacts, and editor noise. Keep `terraform.tfvars.example` committed as the template for new clusters.
