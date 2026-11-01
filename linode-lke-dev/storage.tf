# LKE defaults to linode-block-storage-retain, which leaves the Linode volume (and its bill) behind when a
# PVC is deleted. Make the Delete-policy class the default so deleting a PVC deletes the volume.
resource "kubernetes_annotations" "sc_delete_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "linode-block-storage"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "true"
  }
  force = true # LKE sets annotations on its own classes

  depends_on = [linode_lke_cluster.dev]
}

resource "kubernetes_annotations" "sc_retain_not_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "linode-block-storage-retain"
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }
  force = true

  depends_on = [linode_lke_cluster.dev]
}
