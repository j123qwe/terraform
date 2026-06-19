resource "linode_instance" "node" {
  count  = var.node_count
  label  = "${var.node_label_prefix}-${count.index + 1}"
  region = var.region
  type   = var.instance_type
  image  = var.image

  root_pass           = var.root_pass
  authorized_keys     = var.ssh_authorized_keys
  private_ip          = var.private_ip
  backups_enabled     = var.backups_enabled
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      root_pass,
    ]
  }
}
