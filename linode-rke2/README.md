# Native Linode RKE2 cluster

Independent replacement for `linode-lke-dev`; it does not change or import the LKE
cluster. No state, credentials, kubeconfig or OpenLDAP resources are copied.

## What is deployed

- Ubuntu **24.04 LTS** Linodes with private networking; **3 masters and 3 workers**
  by default. `master_count` accepts only **1 or 3**. Masters run RKE2 server,
  control-plane and embedded etcd, and are tainted against ordinary workloads.
- A Terraform-owned TCP NodeBalancer for **6443** (Kubernetes API) and **9345**
  (RKE2 registration), backed by every master. One master is not HA even though
  it has an API NodeBalancer.
- RKE2's bundled **Cilium + Multus** charts (`cni: [multus, cilium]`). Cilium uses
  VXLAN/Kubernetes IPAM, with kube-proxy retained and CNI exclusivity disabled.
- The official **Linode cloud controller manager (CCM)** and **Block Storage CSI**
  charts, bootstrapped using RKE2's manifest/Helm controller.
- Optional second-stage applications: Traefik, Grafana/Prometheus, cert-manager,
  Linode DNS-01 webhook and the original ClusterIssuer chart. **No OpenLDAP.**

Cilium handles pod networking, not Linode API load-balancer provisioning. The
**Linode CCM** creates NodeBalancers for Kubernetes `Service.type: LoadBalancer`
(including Traefik). Cilium BGP/L2 load-balancer IPAM is deliberately not enabled;
it would compete with the CCM and is not a substitute for a Linode NodeBalancer.

## Prerequisites

- Terraform >= 1.5, Bash, OpenSSH client, and `kubectl` compatible with the pinned
  RKE2 Kubernetes version. Terraform tests require >= 1.9. Helm is only needed for
  local chart linting, not installation.
- A working SSH key pair.
  Nodes are installed over SSH as root. The private key stays on your machine.
- A Linode API token with **Linodes, NodeBalancers, Volumes and Firewall
  read/write**. Applications additionally require **Domains read/write** and an
  existing Linode-hosted DNS zone. API token scopes also need permission to list
  regional/instance metadata used by the integrations.
- A region supporting Block Storage, sufficient quotas for the selected Linode
  plans, NodeBalancers, and dynamically provisioned volumes.

## 1. Build the cluster

```sh
cd linode-rke2
cp .env.example .env
chmod 600 .env
$EDITOR .env
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars  # Set your SSH key paths and node sizing.
terraform init
terraform plan
terraform apply

export KUBECONFIG="$(terraform output -raw kubeconfig_path)"
kubectl get nodes -o wide
kubectl -n kube-system get pods
kubectl get storageclass
```

To use environment authentication instead of a secrets file:

```sh
export LINODE_TOKEN='your-token'
export TF_VAR_linode_token="$LINODE_TOKEN"
```

Terraform cannot read a provider's environment token back out for in-cluster
credentials, so **`TF_VAR_linode_token` is required when using this method**.
The `.env` token takes precedence over `linode_token`. `TF_VAR_cloud_token` can
supply a separate runtime CCM/CSI token. Do not put tokens in committed tfvars.

Bootstrap is ordered: create nodes/network/firewalls, initialize master 1,
join remaining masters, join workers, retrieve a **0600** kubeconfig, then wait
for every node and the networking/cloud/storage components to be ready. Failures
stop the apply with SSH, installer, or Kubernetes diagnostics. RKE2 and Linode
chart versions are pinned rather than silently tracking a release channel.

The CCM HelmChartConfig tolerates any control-plane taint value, including this
stack's `true` value. Without it, the upstream chart's empty-value toleration
prevents CCM scheduling and leaves all nodes cloud-uninitialized, blocking
non-bootstrap Helm jobs (including Multus and CSI).

SSH uses `StrictHostKeyChecking=accept-new` and a cluster-specific
`.bootstrap/<label>/known_hosts`. This is trust-on-first-use: prepopulate that
file with independently verified host keys if required. Changed host keys are
rejected; verify a replacement node's fingerprint before removing its old entry.

## 2. Deploy the applications (optional)

The separate `apps` root avoids Kubernetes/Helm provider initialization before
the cluster and kubeconfig exist. **Use separate state for the two roots**;
do not apply the original LKE state to either root.

```sh
cd apps
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars  # Set domain/acme_email; match cluster_label.
terraform init
terraform plan
terraform apply
terraform output grafana_url
terraform output -raw grafana_admin_password
```

The apps root reads `../.env` and `../kubeconfig-<cluster_label>.yaml` by default.
Override `env_file`/`kubeconfig_path` there too if customized in the infrastructure
root. `dns_token` can separately scope cert-manager's token to DNS changes.
`cert_issuer` defaults to `selfsigned` (untrusted); alternatives are
`letsencrypt-staging` (untrusted, testing) and `letsencrypt-prod`.
`ingress_allowed_cidrs` restricts the **application** NodeBalancer; by default
ports 80/443 are public. Application ingress restrictions do not affect API access.

Unlike managed LKE, control-plane monitoring is enabled. Etcd metrics use the
private node port 2381; scheduler/controller-manager bind metrics listeners to
node interfaces, protected by the node firewall. Grafana and Prometheus use
10Gi and 20Gi CSI PVCs respectively, adding volume charges.

## Storage

The CSI driver dynamically creates and attaches **Linode Volumes** for PVCs:

- `linode-block-storage`: **default**, Delete reclaim policy.
- `linode-block-storage-retain`: opt-in Retain policy for data that should survive
  PVC deletion (and continue billing until you delete the volume).
- Volumes are region-local and **ReadWriteOnce**, not shared RWX storage.
  Minimum size is 10Gi. Expansion is supported, but may require detaching and
  reattaching the volume (restart the consuming pod) for filesystem expansion.
- Volumes are owned by CSI, not individual Terraform `linode_volume` resources.

For example, save this manifest and apply it with `kubectl apply -f`:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: linode-block-storage
  resources:
    requests:
      storage: 10Gi
```

## Networking and Multus

Private node traffic is allowed only from this cluster's private `/32` addresses;
Linode's regional private network is **not a tenant-isolated VPC**. NodeBalancer
backend traffic is allowed from `192.168.255.0/24` to API/registration and
NodePorts. SSH (22) and the API NodeBalancer (6443) allow **all IPv4 sources**
by default for ephemeral labs; `admin_allowed_cidrs` is optional and can restrict
them when needed. SSH keys and Kubernetes credentials are still required, but
public administration endpoints are exposed to internet scanning and attacks.
RKE2 registration (9345) remains restricted to node public addresses; other
firewall protections are unchanged. Pods/services use RKE2's default
10.42.0.0/16 and 10.43.0.0/16 CIDRs.

Multus is installed, but does **not** automatically create secondary networks.
Create NetworkAttachmentDefinitions and pod network annotations for your use
case. Linode guests do not expose physical SR-IOV NICs. Do not assign arbitrary
macvlan IPs/MACs on Linode's public/private network; use an explicitly configured
VLAN/VPC/secondary interface and supported addressing for external attachments.
Additional networks may require deliberate firewall changes. Cluster-wide
secondary IPAM is not configured by this stack.

## Operations and teardown

- Bootstrap scripts/configuration are generated in `.bootstrap` (0600) and
  uploaded to newly created nodes only. **Changing install/chart variables does
  not perform in-place upgrades of existing nodes.** Perform supported rolling
  RKE2 upgrades (one server at a time), maintaining compatible versions across
  servers/agents. Change the RKE2-managed HelmChart/HelmChartConfig manifests
  explicitly for core chart configuration updates.
- Scaling workers up installs new agents. Before removing workers, drain them
  and safely detach/migrate storage. Changing from one to three masters adds
  two servers; reducing three to one or replacing masters requires deliberate
  etcd membership/quorum management, not a blind Terraform apply.
- **Do not blindly replace master 1**: its bootstrap initializes a new cluster.
  Join a replacement to surviving masters or restore an etcd snapshot using
  RKE2's documented recovery procedure. Back up etcd snapshots and the server
  token off-cluster; three servers protect availability, not against data loss.
- If the local kubeconfig is lost, rerun retrieval/readiness without rebuilding:
  `terraform apply -replace=terraform_data.kubeconfig`.
- State and generated bootstrap files contain cluster/runtime credentials.
  Kubeconfig grants cluster-admin. Use encrypted restricted state storage and
  protect all these files; custom kubeconfig paths outside this folder need
  their own ignore rules. The generated default paths and secrets are ignored.
- Deleting a Helm release does not necessarily delete its PVCs. Delete unwanted
  PVCs while CSI is running, check Linode volume deletion, and review Retain
  volumes before tearing down the infrastructure.

```sh
# From linode-rke2, while Kubernetes/CCM/CSI are still running:
terraform -chdir=apps destroy
kubectl get pvc -A
# Delete unwanted PVCs and any other LoadBalancer Services deliberately.
# Wait for their volumes and NodeBalancers to be deleted by CSI/CCM.
terraform destroy
```

The API NodeBalancer is Terraform-owned and deleted by the infrastructure root;
application NodeBalancers and PVC volumes must be cleaned up by CCM/CSI first.
The fetched kubeconfig/known-hosts file is local and not removed by destroy;
remove those specific credential files when no longer needed.

## Offline validation

```sh
terraform init -backend=false
terraform validate
terraform test
terraform -chdir=apps init -backend=false
terraform -chdir=apps validate
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py' -v
bash -n scripts/cluster.sh
helm lint apps/charts/cluster-issuers --set email=you@example.com
```

Terraform tests mock cloud providers and use placeholder credentials/SSH keys;
they do not create Linodes or execute installation provisioners. Python's
standard-library tests render installers and exercise the SSH/kubeconfig helper
with fake commands; they do not contact nodes or change the local kubeconfig.

References: [RKE2 Multus/Cilium](https://docs.rke2.io/networking/multus_sriov),
[Linode CCM](https://github.com/linode/linode-cloud-controller-manager),
[Linode CSI](https://github.com/linode/linode-blockstorage-csi-driver).
