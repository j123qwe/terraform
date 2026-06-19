resource "vultr_instance" "node" {
  count    = var.node_count
  label    = "${var.node_label_prefix}-${count.index + 1}"
  hostname = "${var.hostname_prefix}-${count.index + 1}"

  region = var.region
  plan   = var.plan
  os_id  = var.os_id

  ssh_key_ids = var.ssh_key_ids
  tags        = var.tags
  backups     = var.backups
}
