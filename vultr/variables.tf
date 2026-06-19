variable "vultr_api_key" {
  description = "Vultr API key with full access"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Vultr region slug to deploy resources in"
  type        = string
  default     = "dfw"
}

variable "plan" {
  description = "Vultr instance plan slug"
  type        = string
  default     = "vc2-4c-8gb"
}

variable "os_id" {
  description = "Vultr OS ID (1743 = Ubuntu 22.04 LTS x64)"
  type        = number
  default     = 1743
}

variable "node_count" {
  description = "Number of compute nodes to create"
  type        = number
  default     = 3
}

variable "node_label_prefix" {
  description = "Prefix used when labelling each compute node"
  type        = string
  default     = "node"
}

variable "hostname_prefix" {
  description = "Prefix used for each node's hostname"
  type        = string
  default     = "node"
}

variable "ssh_key_ids" {
  description = "List of Vultr SSH key IDs to inject into each node"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "List of tags to apply to each instance"
  type        = list(string)
  default     = []
}

variable "backups" {
  description = "Enable Vultr managed backups ('enabled' or 'disabled')"
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["enabled", "disabled"], var.backups)
    error_message = "backups must be 'enabled' or 'disabled'."
  }
}
