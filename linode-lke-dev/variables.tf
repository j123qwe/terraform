variable "cluster_label" {
  description = "LKE cluster label"
  type        = string
  default     = "dev-lke"
}

variable "region" {
  description = "Linode region (linode-cli regions list)"
  type        = string
  default     = "us-ord" # Chicago
}

variable "node_type" {
  description = "Node plan. g6-standard-2 = Linode 4GB: 2 vCPU / 4GB RAM / 80GB disk"
  type        = string
  default     = "g6-standard-2"
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "k8s_version" {
  description = "Pin a K8s version (e.g. \"1.34\"). Leave null to use the latest GA version LKE offers."
  type        = string
  default     = null
}

variable "kubeconfig_path" {
  description = "Where to write the kubeconfig locally. Defaults to ./kubeconfig-<label>.yaml"
  type        = string
  default     = null
}

variable "tags" {
  type    = list(string)
  default = ["dev", "terraform"]
}

variable "env_file" {
  description = "Path to a .env-style secrets file containing LINODE_TOKEN=<token>. Defaults to ./.env. If missing, the LINODE_TOKEN env var is used."
  type        = string
  default     = null
}
