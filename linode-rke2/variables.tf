variable "cluster_label" {
  description = "Cluster label and prefix for Linode resources and Kubernetes node names."
  type        = string
  default     = "dev-rke2"
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.cluster_label))
    error_message = "Use 3-30 lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "region" {
  description = "Linode region with Block Storage support."
  type        = string
  default     = "us-ord"
}

variable "master_count" {
  description = "Number of RKE2 server (control-plane/etcd) nodes: 1 or 3."
  type        = number
  default     = 3
  validation {
    condition     = contains([1, 3], var.master_count)
    error_message = "master_count must be 1 or 3 for a single server or an HA etcd quorum."
  }
}

variable "worker_count" {
  description = "Number of dedicated worker nodes."
  type        = number
  default     = 3
  validation {
    condition     = var.worker_count >= 1 && floor(var.worker_count) == var.worker_count
    error_message = "worker_count must be a positive integer."
  }
}

variable "master_type" {
  description = "Linode plan for each master; default is 4 vCPU / 8 GB."
  type        = string
  default     = "g6-standard-4"
}

variable "worker_type" {
  description = "Linode plan for each worker; default is 4 vCPU / 8 GB for monitoring workloads."
  type        = string
  default     = "g6-standard-4"
}

variable "rke2_version" {
  description = "Exact RKE2 release to install on NEW nodes. Existing nodes require a separate rolling upgrade."
  type        = string
  default     = "v1.37.1+rke2r1"
  validation {
    condition     = can(regex("^v1\\.[0-9]+\\.[0-9]+\\+rke2r[0-9]+$", var.rke2_version))
    error_message = "Use an exact RKE2 release such as v1.37.1+rke2r1."
  }
}

variable "ssh_public_key_path" {
  description = "Public SSH key installed for root on every node."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Matching private SSH key used locally for installation and kubeconfig retrieval."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "admin_allowed_cidrs" {
  description = "Optional IPv4 restrictions for SSH and the Kubernetes API. Defaults to public access for ephemeral labs."
  type        = list(string)
  default     = ["0.0.0.0/0"]
  validation {
    condition     = length(var.admin_allowed_cidrs) > 0 && alltrue([for cidr in var.admin_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "Supply at least one valid IPv4 CIDR."
  }
}

variable "kubeconfig_path" {
  description = "Local kubeconfig destination; default ./kubeconfig-<cluster_label>.yaml."
  type        = string
  default     = null
}

variable "env_file" {
  description = ".env-style file containing LINODE_TOKEN. Defaults to ./.env; file token takes precedence."
  type        = string
  default     = null
}

variable "linode_token" {
  description = "Infrastructure API token fallback. Set TF_VAR_linode_token when using environment authentication."
  type        = string
  default     = null
  sensitive   = true
}

variable "cloud_token" {
  description = "Optional separate CCM/CSI token with Linodes, NodeBalancers, Volumes and Firewall read/write; defaults to the infrastructure token."
  type        = string
  default     = null
  sensitive   = true
}

variable "ccm_chart_version" {
  description = "Pinned official ccm-linode chart installed during bootstrap."
  type        = string
  default     = "v0.9.11"
}

variable "csi_chart_version" {
  description = "Pinned official linode-blockstorage-csi-driver chart installed during bootstrap."
  type        = string
  default     = "v1.1.5"
}

variable "tags" {
  type    = list(string)
  default = ["dev", "terraform", "rke2"]
}
