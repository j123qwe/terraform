locals {
  mac_seed = trimspace(var.mac_seed) != "" ? trimspace(var.mac_seed) : var.namespace

  master_nic1_hashes = [
    for i in range(var.master_count) : md5("${local.mac_seed}-${var.master_hostname_prefix}-${i + 1}-nic1")
  ]

  master_nic2_hashes = [
    for i in range(var.master_count) : md5("${local.mac_seed}-${var.master_hostname_prefix}-${i + 1}-nic2")
  ]

  haproxy_nic1_hash = md5("${local.mac_seed}-${var.haproxy_hostname}-nic1")
  haproxy_nic2_hash = md5("${local.mac_seed}-${var.haproxy_hostname}-nic2")

  worker_nic1_hashes = [
    for i in range(var.worker_count) : md5("${local.mac_seed}-${var.worker_hostname_prefix}-${i + 1}-nic1")
  ]

  worker_nic2_hashes = [
    for i in range(var.worker_count) : md5("${local.mac_seed}-${var.worker_hostname_prefix}-${i + 1}-nic2")
  ]

  master_nic1_macs = [
    for h in local.master_nic1_hashes : format(
      "02:%s:%s:%s:%s:%s",
      substr(h, 0, 2),
      substr(h, 2, 2),
      substr(h, 4, 2),
      substr(h, 6, 2),
      substr(h, 8, 2)
    )
  ]

  master_nic2_macs = [
    for h in local.master_nic2_hashes : format(
      "02:%s:%s:%s:%s:%s",
      substr(h, 0, 2),
      substr(h, 2, 2),
      substr(h, 4, 2),
      substr(h, 6, 2),
      substr(h, 8, 2)
    )
  ]

  haproxy_nic1_mac = format(
    "02:%s:%s:%s:%s:%s",
    substr(local.haproxy_nic1_hash, 0, 2),
    substr(local.haproxy_nic1_hash, 2, 2),
    substr(local.haproxy_nic1_hash, 4, 2),
    substr(local.haproxy_nic1_hash, 6, 2),
    substr(local.haproxy_nic1_hash, 8, 2)
  )

  haproxy_nic2_mac = format(
    "02:%s:%s:%s:%s:%s",
    substr(local.haproxy_nic2_hash, 0, 2),
    substr(local.haproxy_nic2_hash, 2, 2),
    substr(local.haproxy_nic2_hash, 4, 2),
    substr(local.haproxy_nic2_hash, 6, 2),
    substr(local.haproxy_nic2_hash, 8, 2)
  )

  worker_nic1_macs = [
    for h in local.worker_nic1_hashes : format(
      "02:%s:%s:%s:%s:%s",
      substr(h, 0, 2),
      substr(h, 2, 2),
      substr(h, 4, 2),
      substr(h, 6, 2),
      substr(h, 8, 2)
    )
  ]

  worker_nic2_macs = [
    for h in local.worker_nic2_hashes : format(
      "02:%s:%s:%s:%s:%s",
      substr(h, 0, 2),
      substr(h, 2, 2),
      substr(h, 4, 2),
      substr(h, 6, 2),
      substr(h, 8, 2)
    )
  ]

  vm_user_common = {
    ssh_pwauth = false
    users = [
      {
        name                = var.vm_username
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        shell               = "/bin/bash"
        lock_passwd         = true
        ssh_authorized_keys = [var.vm_ssh_public_key]
      }
    ]
  }

  vm_netplan_runcmd = [
    "rm -f /etc/netplan/00-installer-config.yaml /etc/netplan/50-cloud-init.yaml || true",
    "netplan generate",
    "netplan apply",
  ]

  vm_guest_agent_packages = ["qemu-guest-agent"]

  vm_guest_agent_runcmd = [
    "systemctl enable qemu-guest-agent || true",
    "systemctl restart qemu-guest-agent || true",
  ]

  haproxy_k8s_config = templatefile("${path.module}/templates/haproxy-k8s.cfg.tftpl", {
    master_ips = [for cidr in var.master_nic1_cidrs : split("/", cidr)[0]]
  })

  haproxy_cloudinit_user_data = join("\n", [
    "#cloud-config",
    yamlencode(merge(local.vm_user_common, {
      package_update = true
      packages       = concat(local.vm_guest_agent_packages, ["haproxy"])
      write_files = [
        {
          path        = "/etc/netplan/99-harvester-static.yaml"
          permissions = "0644"
          content = yamlencode({
            network = {
              version = 2
              ethernets = {
                nic1 = {
                  match = {
                    macaddress = lower(local.haproxy_nic1_mac)
                  }
                  dhcp4     = false
                  addresses = [var.haproxy_nic1_cidr]
                  routes = [
                    {
                      to  = "default"
                      via = var.nic1_gateway
                    }
                  ]
                  nameservers = {
                    addresses = var.nic1_dns_servers
                  }
                }
                nic2 = {
                  match = {
                    macaddress = lower(local.haproxy_nic2_mac)
                  }
                  dhcp4     = false
                  addresses = [var.haproxy_nic2_cidr]
                }
              }
            }
          })
        },
        {
          path        = "/tmp/haproxy.cfg"
          permissions = "0644"
          content     = local.haproxy_k8s_config
        }
      ]
      runcmd = concat(local.vm_netplan_runcmd, local.vm_guest_agent_runcmd, [
        "install -o root -g root -m 0644 /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg",
        "haproxy -c -f /etc/haproxy/haproxy.cfg",
        "systemctl enable haproxy",
        "systemctl restart haproxy",
      ])
    }))
  ])
}

resource "kubernetes_namespace" "vm_namespace" {
  metadata {
    name = var.namespace
  }
}

resource "harvester_virtualmachine" "masters" {
  count = var.master_count

  name      = "${var.master_hostname_prefix}-${count.index + 1}"
  hostname  = "${var.master_hostname_prefix}-${count.index + 1}"
  namespace = kubernetes_namespace.vm_namespace.metadata[0].name

  cpu    = var.master_cpu
  memory = var.master_memory

  network_interface {
    name         = "nic-1"
    network_name = var.nic1_network_name
    mac_address  = local.master_nic1_macs[count.index]
  }

  network_interface {
    name         = "nic-2"
    network_name = var.nic2_network_name
    mac_address  = local.master_nic2_macs[count.index]
  }

  disk {
    name               = "disk0"
    type               = "disk"
    size               = var.master_root_disk_size
    bus                = "virtio"
    boot_order         = 1
    image              = var.image_id
    auto_delete        = true
  }

  cloudinit {
    user_data = join("\n", [
      "#cloud-config",
      yamlencode(merge(local.vm_user_common, {
        package_update = true
        packages       = local.vm_guest_agent_packages
        write_files = [
          {
            path        = "/etc/netplan/99-harvester-static.yaml"
            permissions = "0644"
            content = yamlencode({
              network = {
                version = 2
                ethernets = {
                  nic1 = {
                    match = {
                      macaddress = lower(local.master_nic1_macs[count.index])
                    }
                    dhcp4     = false
                    addresses = [var.master_nic1_cidrs[count.index]]
                    routes = [
                      {
                        to  = "default"
                        via = var.nic1_gateway
                      }
                    ]
                    nameservers = {
                      addresses = var.nic1_dns_servers
                    }
                  }
                  nic2 = {
                    match = {
                      macaddress = lower(local.master_nic2_macs[count.index])
                    }
                    dhcp4     = false
                    addresses = [var.master_nic2_cidrs[count.index]]
                  }
                }
              }
            })
          }
        ]
        runcmd = concat(local.vm_netplan_runcmd, local.vm_guest_agent_runcmd)
      }))
    ])
  }
}

resource "harvester_virtualmachine" "workers" {
  count = var.worker_count

  name      = "${var.worker_hostname_prefix}-${count.index + 1}"
  hostname  = "${var.worker_hostname_prefix}-${count.index + 1}"
  namespace = kubernetes_namespace.vm_namespace.metadata[0].name

  cpu    = var.worker_cpu
  memory = var.worker_memory

  network_interface {
    name         = "nic-1"
    network_name = var.nic1_network_name
    mac_address  = local.worker_nic1_macs[count.index]
  }

  network_interface {
    name         = "nic-2"
    network_name = var.nic2_network_name
    mac_address  = local.worker_nic2_macs[count.index]
  }

  disk {
    name               = "disk0"
    type               = "disk"
    size               = var.worker_root_disk_size
    bus                = "virtio"
    boot_order         = 1
    image              = var.image_id
    auto_delete        = true
  }

  dynamic "disk" {
    for_each = var.worker_extra_disk_size != "" ? [var.worker_extra_disk_size] : []

    content {
      name        = "disk1"
      type        = "disk"
      size        = disk.value
      bus         = "virtio"
      auto_delete = true
    }
  }

  cloudinit {
    user_data_secret_name = harvester_cloudinit_secret.workers[count.index].name
  }
}

resource "harvester_cloudinit_secret" "workers" {
  count = var.worker_count

  name      = "${var.worker_hostname_prefix}-${count.index + 1}-cloudinit"
  namespace = kubernetes_namespace.vm_namespace.metadata[0].name

  user_data = join("\n", [
    "#cloud-config",
    yamlencode(merge(local.vm_user_common, {
      package_update = true
      packages = concat(
        local.vm_guest_agent_packages,
        var.worker_extra_disk_size != "" ? ["parted", "xfsprogs"] : []
      )
      write_files = concat([
        {
          path        = "/etc/netplan/99-harvester-static.yaml"
          permissions = "0644"
          content = yamlencode({
            network = {
              version = 2
              ethernets = {
                nic1 = {
                  match = {
                    macaddress = lower(local.worker_nic1_macs[count.index])
                  }
                  dhcp4     = false
                  addresses = [var.worker_nic1_cidrs[count.index]]
                  routes = [
                    {
                      to  = "default"
                      via = var.nic1_gateway
                    }
                  ]
                  nameservers = {
                    addresses = var.nic1_dns_servers
                  }
                }
                nic2 = {
                  match = {
                    macaddress = lower(local.worker_nic2_macs[count.index])
                  }
                  dhcp4     = false
                  addresses = [var.worker_nic2_cidrs[count.index]]
                }
              }
            }
          })
        }
        ], var.worker_extra_disk_size != "" ? [{
          path        = "/usr/local/sbin/setup-worker-extra-disk.sh"
          permissions = "0755"
          content     = <<-EOT
            #!/usr/bin/env bash
            set -euo pipefail

            MOUNT_PATH="${var.worker_extra_disk_mount_path}"
            FS_LABEL="worker-storage"
            FSTAB_ENTRY="LABEL=$FS_LABEL $MOUNT_PATH xfs defaults,nofail 0 2"

            mkdir -p "$MOUNT_PATH"

            # If the labeled filesystem already exists, ensure it is mounted and persisted.
            EXISTING_DEVICE="$(blkid -L "$FS_LABEL" || true)"
            if [[ -n "$EXISTING_DEVICE" ]]; then
              if ! grep -qsE "^[^#].*[[:space:]]$MOUNT_PATH[[:space:]]" /etc/fstab; then
                echo "$FSTAB_ENTRY" >> /etc/fstab
              fi
              mountpoint -q "$MOUNT_PATH" || mount "$MOUNT_PATH"
              exit 0
            fi

            ROOT_SOURCE="$(findmnt -n -o SOURCE / || true)"
            ROOT_DISK_NAME=""
            if [[ -n "$ROOT_SOURCE" ]]; then
              ROOT_DISK_NAME="$(lsblk -no PKNAME "$ROOT_SOURCE" 2>/dev/null || true)"
            fi

            TARGET_DISK=""
            while IFS= read -r DISK_PATH; do
              DISK_NAME="$(basename "$DISK_PATH")"
              if [[ -n "$ROOT_DISK_NAME" && "$DISK_NAME" == "$ROOT_DISK_NAME" ]]; then
                continue
              fi

              # Skip disks that already contain partitions.
              if lsblk -n -o TYPE "$DISK_PATH" | grep -q "^part$"; then
                continue
              fi

              TARGET_DISK="$DISK_PATH"
              break
            done < <(lsblk -dn -o PATH,TYPE | awk '$2 == "disk" { print $1 }')

            if [[ -z "$TARGET_DISK" ]]; then
              exit 0
            fi

            parted -s "$TARGET_DISK" mklabel gpt
            parted -s -a optimal "$TARGET_DISK" mkpart primary xfs 0% 100%
            partprobe "$TARGET_DISK" || true
            udevadm settle || true

            TARGET_PART="$(lsblk -nr -o PATH,TYPE "$TARGET_DISK" | awk '$2 == "part" { print $1; exit }')"
            if [[ -z "$TARGET_PART" ]]; then
              echo "No partition detected after partitioning $TARGET_DISK" >&2
              exit 1
            fi

            mkfs.xfs -f -L "$FS_LABEL" "$TARGET_PART"

            if ! grep -qsE "^[^#].*[[:space:]]$MOUNT_PATH[[:space:]]" /etc/fstab; then
              echo "$FSTAB_ENTRY" >> /etc/fstab
            fi

            mountpoint -q "$MOUNT_PATH" || mount "$MOUNT_PATH"
          EOT
      }] : [])
      runcmd = concat(
        local.vm_netplan_runcmd,
        local.vm_guest_agent_runcmd,
        var.worker_extra_disk_size != "" ? ["/usr/local/sbin/setup-worker-extra-disk.sh"] : []
      )
    }))
  ])
}

resource "harvester_cloudinit_secret" "haproxy" {
  name      = "${var.haproxy_hostname}-cloudinit"
  namespace = kubernetes_namespace.vm_namespace.metadata[0].name
  user_data = local.haproxy_cloudinit_user_data
}

resource "harvester_virtualmachine" "haproxy" {
  name      = var.haproxy_hostname
  hostname  = var.haproxy_hostname
  namespace = kubernetes_namespace.vm_namespace.metadata[0].name

  cpu    = var.master_cpu
  memory = var.master_memory

  network_interface {
    name         = "nic-1"
    network_name = var.nic1_network_name
    mac_address  = local.haproxy_nic1_mac
  }

  network_interface {
    name         = "nic-2"
    network_name = var.nic2_network_name
    mac_address  = local.haproxy_nic2_mac
  }

  disk {
    name               = "disk0"
    type               = "disk"
    size               = var.master_root_disk_size
    bus                = "virtio"
    boot_order         = 1
    image              = var.image_id
    auto_delete        = true
  }

  cloudinit {
    user_data_secret_name = harvester_cloudinit_secret.haproxy.name
  }
}