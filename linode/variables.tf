variable "linode_token" {
  description = "Linode API token with read/write access"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Linode region to deploy resources in"
  type        = string
  default     = "us-central"
}

variable "instance_type" {
  description = "Linode instance plan type for each node"
  type        = string
  default     = "g6-standard-4"
}

variable "image" {
  description = "OS image to use for each node"
  type        = string
  default     = "linode/ubuntu22.04"
}

variable "node_count" {
  description = "Number of compute nodes to create"
  type        = number
  default     = 3
}

variable "node_label_prefix" {
  description = "Prefix used when naming each compute node"
  type        = string
  default     = "node"
}

variable "root_pass" {
  description = "Root password for each compute node"
  type        = string
  sensitive   = true
}

variable "ssh_authorized_keys" {
  description = "List of SSH public keys to add to each node"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "List of tags to apply to each Linode instance"
  type        = list(string)
  default     = []
}

variable "private_ip" {
  description = "Enable private IP networking for each node"
  type        = bool
  default     = true
}

variable "backups_enabled" {
  description = "Enable Linode managed backups for each node"
  type        = bool
  default     = false
}
