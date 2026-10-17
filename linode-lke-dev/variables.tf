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

variable "domain" {
  description = "Linode-hosted DNS zone used for DNS-01 challenges and app hostnames (must already exist in Linode DNS)"
  type        = string
}

variable "acme_email" {
  description = "Email for the Let's Encrypt account (expiry notices)"
  type        = string
}

variable "cert_issuer" {
  description = "ClusterIssuer used for app certificates. Defaults to staging (untrusted certs, no rate limits); set to letsencrypt-prod for trusted certificates."
  type        = string
  default     = "letsencrypt-staging"
}

variable "grafana_host" {
  description = "Grafana hostname; defaults to grafana.<domain>"
  type        = string
  default     = null
}

variable "dns_token" {
  description = "Linode token (Domains read/write) for the cert-manager DNS-01 webhook. Only needed if LINODE_TOKEN is not in the .env file."
  type        = string
  default     = null
  sensitive   = true
}
