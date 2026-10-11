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
- Optional `disk1` for workers via `worker_extra_disk_size` (for example, Longhorn data disk)
- When `worker_extra_disk_size` is set, cloud-init partitions `disk1`, formats it as XFS, mounts it at `worker_extra_disk_mount_path`, and writes an `/etc/fstab` entry.

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
- Optional for storage workloads:
   - `worker_extra_disk_size` (set, for example, `200Gi`; leave empty to skip creating `disk1`)
   - `worker_extra_disk_mount_path` (default `/var/lib/longhorn`)

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

### Package installation fails before HAProxy starts

Static networking is supplied through NoCloud `network_data`, so cloud-init
configures addresses, the default route, and DNS before installing packages.
The previous setup applied Netplan in `runcmd`, which runs after package
installation. Without working fallback networking, apt failed to resolve Ubuntu
repositories and HAProxy was never installed. Earlier success could have depended
on DHCP or networking already present in the image.

For a fresh disposable HAProxy VM, review a replacement plan before applying it:

```sh
tofu plan -replace=harvester_virtualmachine.haproxy
tofu apply -replace=harvester_virtualmachine.haproxy
```

Replacement deletes the VM's root disk. Updating a cloud-init secret alone does
not rerun first-boot provisioning on an existing VM. Masters and workers also use
early network-data now; do not replace nodes containing data without a migration
or backup plan.

To repair the existing HAProxy VM without replacement, use its console or SSH
and run these commands on the VM:

```sh
sudo chmod 0600 /etc/netplan/99-harvester-static.yaml
sudo netplan generate
sudo netplan apply
ip -4 address
ip -4 route
getent hosts archive.ubuntu.com security.ubuntu.com
```

Confirm the static addresses, default route, and DNS resolution before proceeding.
If resolution still fails, check NIC1 VLAN connectivity, gateway reachability,
and access to the configured DNS servers.

```sh
sudo apt-get update && sudo apt-get install -y qemu-guest-agent haproxy
```

Only after installation succeeds, copy the staged custom configuration and start
the services:

```sh
sudo install -o root -g root -m 0644 /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg
sudo haproxy -c -f /etc/haproxy/haproxy.cfg && sudo systemctl enable --now haproxy && sudo systemctl restart haproxy
sudo systemctl start qemu-guest-agent
sudo systemctl status haproxy qemu-guest-agent --no-pager
```

The failed build staged the configuration at `/tmp/haproxy.cfg`; if it has been
removed, restore the rendered custom config first. New builds stage it at
`/var/lib/cloud/haproxy.cfg` instead. Run `sudo cloud-init status --long` to inspect
provisioning status; manual repair does not clear the original failure record.

### VM connectivity issues

- Verify VLAN0 reachability from your workstation to all node NIC1 addresses
- Verify `vm_username` matches image user
- Verify private key path and public key pairing

## State and Team Usage Notes

This project currently uses local state. For multi-user or CI-driven labs, use a remote backend (for example S3-compatible object storage with locking) before team-scale use.

## Git Hygiene

The included `.gitignore` excludes state files, tfvars, local artifacts, and editor noise. Keep `terraform.tfvars.example` committed as the template for new clusters.
