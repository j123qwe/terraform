variable "namespace" {
  description = "Namespace where VMs are created"
  type        = string
  default     = "default"
}

variable "mac_seed" {
  description = "Optional seed to make generated MAC addresses unique across lab clusters"
  type        = string
  default     = ""
}

variable "image_id" {
  description = "Harvester image ID used for VM disk0 (example: default/ubuntu-22.04-cloudimg-amd64)"
  type        = string
}

variable "master_hostname_prefix" {
  description = "Hostname prefix for master nodes"
  type        = string
  default     = "k8s-master"
}

variable "haproxy_hostname" {
  description = "Hostname for the HAProxy node"
  type        = string
  default     = "k8s-haproxy-1"
}

variable "worker_hostname_prefix" {
  description = "Hostname prefix for worker nodes"
  type        = string
  default     = "worker"
}

variable "master_count" {
  description = "Number of master VMs"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of worker VMs"
  type        = number
  default     = 3
}

variable "vm_username" {
  description = "OS username injected via cloud-init"
  type        = string
}

variable "vm_ssh_public_key" {
  description = "SSH public key injected via cloud-init"
  type        = string
}

variable "nic1_network_name" {
  description = "Harvester network for NIC1 (VLAN0)"
  type        = string
  default     = "default/vlan0"
}

variable "nic2_network_name" {
  description = "Harvester network for NIC2 (VLAN111)"
  type        = string
  default     = "default/vlan111"
}

variable "nic1_gateway" {
  description = "Gateway used on NIC1"
  type        = string
}

variable "nic1_dns_servers" {
  description = "DNS servers used on NIC1"
  type        = list(string)
}

variable "master_nic1_cidrs" {
  description = "Master NIC1 addresses in CIDR format"
  type        = list(string)

  validation {
    condition     = length(var.master_nic1_cidrs) == var.master_count
    error_message = "master_nic1_cidrs must contain exactly master_count IP/CIDR entries."
  }
}

variable "haproxy_nic1_cidr" {
  description = "HAProxy NIC1 address in CIDR format"
  type        = string
}

variable "master_nic2_cidrs" {
  description = "Master NIC2 addresses in CIDR format"
  type        = list(string)

  validation {
    condition     = length(var.master_nic2_cidrs) == var.master_count
    error_message = "master_nic2_cidrs must contain exactly master_count IP/CIDR entries."
  }
}

variable "haproxy_nic2_cidr" {
  description = "HAProxy NIC2 address in CIDR format"
  type        = string
}

variable "worker_nic1_cidrs" {
  description = "Worker NIC1 addresses in CIDR format"
  type        = list(string)

  validation {
    condition     = length(var.worker_nic1_cidrs) == var.worker_count
    error_message = "worker_nic1_cidrs must contain exactly worker_count IP/CIDR entries."
  }
}

variable "worker_nic2_cidrs" {
  description = "Worker NIC2 addresses in CIDR format"
  type        = list(string)

  validation {
    condition     = length(var.worker_nic2_cidrs) == var.worker_count
    error_message = "worker_nic2_cidrs must contain exactly worker_count IP/CIDR entries."
  }
}

variable "master_root_disk_size" {
  description = "Master disk0 size"
  type        = string
  default     = "50Gi"
}

variable "worker_root_disk_size" {
  description = "Worker disk0 size"
  type        = string
  default     = "100Gi"
}

variable "master_cpu" {
  description = "vCPU count for master VM"
  type        = number
  default     = 4
}

variable "master_memory" {
  description = "Memory for master VM"
  type        = string
  default     = "8Gi"
}

variable "worker_cpu" {
  description = "vCPU count for worker VMs"
  type        = number
  default     = 2
}

variable "worker_memory" {
  description = "Memory for worker VMs"
  type        = string
  default     = "4Gi"
}
