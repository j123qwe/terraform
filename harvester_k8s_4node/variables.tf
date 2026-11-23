variable "harvester_kubeconfig" {
  description = "Kubeconfig for Harvester, not the new RKE2 cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "namespace" {
  description = "New Harvester namespace for the VMs."
  type        = string
  validation {
    condition     = length(var.namespace) <= 63 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a DNS label of at most 63 characters."
  }
}

variable "mac_seed" {
  description = "Unique seed for deterministic MAC addresses; defaults to namespace."
  type        = string
  default     = ""
}

variable "image_id" {
  description = "Harvester Ubuntu cloud image ID, e.g. default/ubuntu-24.04."
  type        = string
}

variable "vm_username" {
  description = "Cloud-init user with passwordless sudo."
  type        = string
  default     = "ubuntu"
  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]*$", var.vm_username))
    error_message = "vm_username must be a valid lowercase Linux username."
  }
}

variable "vm_ssh_public_key" {
  description = "Public SSH key installed in the VMs."
  type        = string
}

variable "ssh_private_key_path" {
  description = "Private key corresponding to vm_ssh_public_key."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "verify_ssh_host_keys" {
  description = "Verify SSH host keys using per-node trust-on-first-use files. False accepts any host key."
  type        = bool
  default     = false
}

variable "domain" {
  description = "DNS suffix used to derive the default Grafana hostname."
  type        = string
  default     = "nip.io"
  validation {
    condition = var.domain == null ? false : length(var.domain) <= 245 && alltrue([
      for label in split(".", var.domain) : length(label) <= 63 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", label))
    ])
    error_message = "domain is required and must be a lowercase DNS hostname of at most 245 characters, without a trailing dot."
  }
}

variable "acme_email" {
  description = "Reserved for future ACME configuration; unused by the self-signed issuer."
  type        = string
  default     = null
}

variable "grafana_host" {
  description = "Grafana ingress hostname; defaults to grafana.<Traefik IP>.<domain>."
  type        = string
  default     = null
  validation {
    condition = var.grafana_host == null ? true : length(var.grafana_host) <= 253 && alltrue([
      for label in split(".", var.grafana_host) : length(label) <= 63 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", label))
    ])
    error_message = "grafana_host must be a lowercase DNS hostname without a trailing dot."
  }
}

variable "traefik_load_balancer_ip" {
  description = "Reserved IPv4 address for Traefik, inside or outside the default Cilium pool."
  type        = string
  default     = null
  validation {
    condition     = var.traefik_load_balancer_ip == null ? true : try(cidrhost("${var.traefik_load_balancer_ip}/32", 0) == var.traefik_load_balancer_ip && can(cidrnetmask("${var.traefik_load_balancer_ip}/32")), false)
    error_message = "traefik_load_balancer_ip must be a single IPv4 address."
  }
}

variable "master_hostname" {
  description = "RKE2 server hostname."
  type        = string
  default     = "k8s-master-1"
  validation {
    condition     = length(var.master_hostname) <= 63 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.master_hostname))
    error_message = "master_hostname must be a DNS label of at most 63 characters."
  }
}

variable "worker_hostname_prefix" {
  description = "Worker hostname prefix; -1 through -3 are appended."
  type        = string
  default     = "k8s-worker"
  validation {
    condition     = length(var.worker_hostname_prefix) <= 61 && can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.worker_hostname_prefix))
    error_message = "worker_hostname_prefix must be a DNS label of at most 61 characters."
  }
}

variable "nic1_network_name" {
  description = "Harvester network for primary NIC."
  type        = string
  default     = "default/vlan0"
}

variable "nic2_network_name" {
  description = "Harvester network for secondary NIC."
  type        = string
  default     = "default/vlan111"
}

variable "nic1_gateway" {
  description = "IPv4 gateway for the primary NIC."
  type        = string
}

variable "nic1_dns_servers" {
  description = "DNS servers for the primary NIC."
  type        = list(string)
}

variable "master_nic1_cidr" {
  description = "Server primary IPv4 address and prefix."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.master_nic1_cidr))
    error_message = "master_nic1_cidr must be an IPv4 CIDR."
  }
}

variable "master_nic2_cidr" {
  description = "Server secondary IPv4 address and prefix."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.master_nic2_cidr))
    error_message = "master_nic2_cidr must be an IPv4 CIDR."
  }
}

variable "worker_nic1_cidrs" {
  description = "Three worker primary IPv4 addresses and prefixes."
  type        = list(string)
  validation {
    condition     = length(var.worker_nic1_cidrs) == 3 && alltrue([for cidr in var.worker_nic1_cidrs : can(cidrnetmask(cidr))])
    error_message = "worker_nic1_cidrs must contain exactly three IPv4 CIDRs."
  }
}

variable "worker_nic2_cidrs" {
  description = "Three worker secondary IPv4 addresses and prefixes."
  type        = list(string)
  validation {
    condition     = length(var.worker_nic2_cidrs) == 3 && alltrue([for cidr in var.worker_nic2_cidrs : can(cidrnetmask(cidr))])
    error_message = "worker_nic2_cidrs must contain exactly three IPv4 CIDRs."
  }
}

variable "master_cpu" {
  type    = number
  default = 4
}
variable "master_memory" {
  type    = string
  default = "8Gi"
}
variable "master_root_disk_size" {
  type    = string
  default = "50Gi"
}
variable "worker_cpu" {
  type    = number
  default = 4
}
variable "worker_memory" {
  type    = string
  default = "8Gi"
}
variable "worker_root_disk_size" {
  type    = string
  default = "100Gi"
}

variable "rke2_version" {
  description = "Exact RKE2 version installed on newly created nodes."
  type        = string
  default     = "v1.37.1+rke2r1"
  validation {
    condition     = can(regex("^v1\\.[0-9]+\\.[0-9]+\\+rke2r[0-9]+$", var.rke2_version))
    error_message = "Use an exact RKE2 release such as v1.37.1+rke2r1."
  }
}

variable "load_balancer_ip_range" {
  description = "Inclusive IPv4 range reserved for Cilium LoadBalancer services."
  type = object({
    start = string
    stop  = string
  })
  validation {
    condition = try(
      can(cidrnetmask("${var.load_balancer_ip_range.start}/32")) &&
      can(cidrnetmask("${var.load_balancer_ip_range.stop}/32")) &&
      sum([for i, n in split(".", var.load_balancer_ip_range.start) : tonumber(n) * pow(256, 3 - i)]) <=
      sum([for i, n in split(".", var.load_balancer_ip_range.stop) : tonumber(n) * pow(256, 3 - i)]),
      false
    )
    error_message = "Provide valid IPv4 start and stop addresses in ascending order."
  }
}

variable "l2_announcement_interface" {
  description = "Cilium interface regex; null detects the common primary interface name on the workers."
  type        = string
  default     = null
  validation {
    condition     = var.l2_announcement_interface == null ? true : length(trimspace(var.l2_announcement_interface)) > 0 && can(regexall(var.l2_announcement_interface, ""))
    error_message = "Provide a nonempty RE2-compatible interface regular expression."
  }
}
