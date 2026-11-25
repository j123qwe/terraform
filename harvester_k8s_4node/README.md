# Four-node Harvester RKE2 cluster

This independent Terraform root creates **one RKE2 server and three dedicated
workers** on Harvester, then installs RKE2 over SSH. The server runs the
control plane and embedded etcd; it is a single point of failure. Its primary
IP is used directly for the Kubernetes API (6443), RKE2 registration (9345),
and Cilium bootstrap. There is no HAProxy VM and no highly available API.
The existing `harvester_k8s_3node` and `harvester_k8s_6node` roots only create
VMs, cloud-init configuration, and HAProxy; they do not install Kubernetes.

Each VM has two statically configured NICs, matched by cloud-init using their
generated MAC addresses without renaming them. RKE2 uses the primary IP
for node communication. The control-plane node is tainted and excluded from
the L2 policy. RKE2's bundled Multus and Cilium provide pod networking.
The same Terraform root installs Longhorn, Traefik, cert-manager, and
kube-prometheus-stack after the cluster is ready. Multus does not
automatically create secondary pod networks.

## Cilium and addressing

The bundled Cilium chart enables `l2announcements`, `bgpControlPlane`, and
`kubeProxyReplacement`; RKE2 kube-proxy is disabled. The API server's direct IP
avoids a dependency on Kubernetes service routing during bootstrap. The
`load_balancer_ip_range` start and stop addresses in `terraform.tfvars` create
the default CiliumLoadBalancerIPPool. A default CiliumL2AnnouncementPolicy
announces LoadBalancer IPs from workers on the interface carrying each
worker's configured primary IP. Bootstrap discovers that name over SSH and
requires it to be the same on all three workers; if names differ, configure
`l2_announcement_interface` as an RE2 regular expression matching the intended
interface on each worker. The override can also select a different interface.
It must match interfaces Cilium selects as service devices, and the pool must
be on that interface's LAN. Previously copied tfvars containing
`l2_announcement_interface = "^primary0$"` must remove that line to enable
discovery or replace it with an appropriate override.

Reserve the whole pool outside DHCP and all node, gateway, and other assigned
addresses. The LAN/Harvester network must allow the workers to respond to ARP
for those IPs and clients must be able to reach that LAN. Cilium L2 announcements
are beta and do not support `externalTrafficPolicy: Local` reliably; use
`Cluster`. Each service IP has one announcing worker at a time. This is for
workload services, **not** API/registration bootstrap.

BGP is enabled but **no BGP peers or advertisements are configured**: configure
Cilium BGP resources and your routers separately before expecting BGP routes.
L2 announcements alone do not advertise beyond the local network.
The Cilium API client rate limit is set to 20 QPS / 40 burst for a small lab;
size it for the number of announced services using Cilium's guidance.

## Prerequisites

- Terraform >= 1.5, Bash, OpenSSH, and a compatible local `kubectl`. Tests use
  Terraform >= 1.9 and Python 3.
- A Harvester kubeconfig and permission to create a **new** namespace, VMs,
  and related resources. Set `harvester_kubeconfig` if not `~/.kube/config`.
  Destroy deletes the Terraform-created namespace and its contents.
- An Ubuntu 24.04 cloud image with cloud-init/netplan, systemd, and a kernel
  supported by the bundled Cilium version. Nodes need outbound access to Ubuntu
  repositories, the RKE2 installer and release artifacts, and the Longhorn
  container images. Harvester's guest agent package is installed during
  cloud-init. Bootstrap installs `open-iscsi` and `nfs-common` and enables
  `iscsid` for Longhorn.
- Longhorn 1.13.0 requires Kubernetes 1.34 or newer, privileged workloads, and
  a supported host filesystem with mount propagation. See the
  [Longhorn installation requirements](https://longhorn.io/docs/1.13.0/deploy/install/).
- Two existing Harvester networks, unique static addresses, gateway and DNS.
  The machine running Terraform must reach all primary IPs over SSH and the
  server over TCP 6443. Nodes need mutual RKE2/Cilium connectivity; see the
  RKE2 networking requirements and allow TCP 9345 and 6443 among nodes.
- An SSH keypair; cloud-init creates `vm_username` with passwordless sudo and
  installs `vm_ssh_public_key`. Terraform uses the matching private key.

## Deploy and inspect

```sh
cd harvester_k8s_4node
cp terraform.tfvars.example terraform.tfvars
# Edit image, networks, addresses, SSH keys, and reserved LB IP range.
terraform init
terraform validate
terraform plan
terraform apply
export KUBECONFIG="$(terraform output -raw kubeconfig_path)"
kubectl get nodes -o wide
kubectl -n kube-system get pods
kubectl get ciliumloadbalancerippools,ciliuml2announcementpolicies
kubectl -n longhorn-system get pods
kubectl get storageclass
```

Terraform waits for cloud-init, installs the server before the workers, retrieves
a mode-0600 kubeconfig, waits for all nodes and Cilium/Multus, then applies the
pool and policy after their CRDs are established and checks for pool conflicts.
Terraform then deploys the applications using the generated kubeconfig. A
single plan and apply manage both the cluster and apps.
An apply failure should be
investigated using cloud-init, RKE2 journals and Helm jobs before retrying.
RKE2 services are allowed time to recover from transient startup failures,
such as an image registry being temporarily unreachable. If startup still
fails after 10 minutes, inspect the reported service journal and retry
`terraform apply` after resolving the underlying issue.
By default SSH **does not verify host keys** and ignores both user and system
known-hosts files, so reused IPs work without removing old entries. This permits
man-in-the-middle attacks and can expose the join token and cluster-admin
kubeconfig. For trusted environments only; set `verify_ssh_host_keys = true` to
use trust-on-first-use with `StrictHostKeyChecking=accept-new`. In that mode,
prepopulate the per-node files under `.bootstrap/<namespace>/` with independently
verified keys if needed; verify a replacement's identity before removing its
old entry.
Protect and back up the kubeconfig. If it is lost, restore it before running
Terraform; the Kubernetes and Helm providers need it to refresh existing apps.

## Applications

The apps are managed in the same Terraform state as the cluster. In
`terraform.tfvars`, set `domain`
(defaults to `nip.io`), and optionally `traefik_load_balancer_ip` and
`grafana_host`. For example, with Traefik at `192.168.86.55`, Grafana defaults
to `grafana.192.168.86.55.nip.io`. The `grafana_host` override replaces that
name in the ingress and certificate. The selected self-signed issuer does not
use `acme_email`; the value is reserved for future ACME configuration. No
Let's Encrypt issuers, DNS challenge solvers, or DNS records are created.

### Storage

Longhorn provides the default `longhorn` StorageClass for dynamically
provisioned PVCs. Its volumes use **one replica**: a node or disk failure can
make a volume unavailable or permanently lose its data. Back up important
data to a separate location; no backup target is configured here. The default
class uses the `Delete` reclaim policy, so deleting a PVC deletes its volume.
Longhorn stores data under `/var/lib/longhorn` on the workers' root disks;
capacity is shared with the OS and Kubernetes. Monitor free space and Longhorn
disk scheduling. The tainted control-plane node is not used for storage.

Existing volumes are not changed, and Longhorn's UI-created volumes have
their own replica setting. If another default StorageClass already exists,
remove its default annotation to avoid ambiguous default selection. Bootstrap
does not rerun on existing nodes, so verify their iSCSI and NFS prerequisites
before applying to an existing cluster.

### Ingress and monitoring

The optional `traefik_load_balancer_ip` requests a specific IPv4 address. It
may be inside the default pool or outside it on the announcement LAN. For an
outside address Terraform creates a dedicated single-address Cilium pool
restricted to the Traefik Service, and checks for pool conflicts before
installing Traefik. Reserve the address outside DHCP and other allocations,
including all other Cilium pools. If it is inside the default pool, other
services can allocate it before Traefik; choose an unused address and verify
availability. Cilium must assign the requested IP before Grafana is updated;
an unavailable IP or conflicting pool fails the deployment. Inspect Service
events and Cilium pool status if allocation fails.

If `traefik_load_balancer_ip` is unset, Cilium allocates an address from the
default pool and Terraform derives Grafana's hostname from that address.
If an automatically allocated address later changes, reapply Terraform to
update the hostname and certificate. A static IP or hostname change may
interrupt ingress and reissue the certificate.

Review the plan before applying, including any Harvester provider drift.

```sh
terraform output -raw traefik_lb_ip
terraform output grafana_url
terraform output -raw grafana_admin_password
```

`nip.io` resolves names containing the IP to that address; it exposes the
encoded private IP in DNS queries, and DNS rebinding protection may block
private-address responses. Use local DNS or a hosts entry if needed. For a
different domain, provide an appropriate DNS A record. Cilium announces the
address on the worker LAN; reachability from other networks must be configured
separately. Traefik redirects HTTP to HTTPS. The self-signed certificate is
**not trusted by browsers** and is for lab use; no public certificate is issued.

Grafana and Prometheus use **ephemeral storage**, as in `linode-lke-dev`:
Grafana changes and metrics can be lost when pods are recreated. Neither app
uses a PVC. Scraping etcd, controller-manager,
scheduler, and kube-proxy is disabled because their metrics are not exposed
by this configuration and Cilium replaces kube-proxy.

Terraform state contains the generated Grafana password; the Kubernetes secret
and sensitive Terraform output contain it too. Protect the state and restrict
cluster access. Before destroying the cluster, back up needed volume data,
remove workloads and PVCs using Longhorn, then explicitly enable Longhorn's
uninstall confirmation. This is destructive and permits the Helm uninstall
hook to remove Longhorn data and resources:

```sh
kubectl -n longhorn-system patch -p '{"value":"true"}' --type=merge settings.longhorn.io deleting-confirmation-flag
terraform destroy
```

See the [Longhorn uninstall guide](https://longhorn.io/docs/1.13.0/deploy/uninstall/)
for details and recovery from an unsuccessful uninstall. Helm removes the apps
before the infrastructure so it can still reach the cluster.

Earlier versions used a separate `apps` state. Do not apply this unified
configuration to an existing cluster whose apps are still managed by that
state without first migrating or removing those releases; otherwise Terraform
will try to install releases that already exist. For a destroyed cluster,
the old state is no longer used and can be retained as a sensitive backup.

### Static addresses missing on previously created VMs

Older versions requested interface renames to `primary0`/`secondary0`. On some
images DHCP activates interfaces before cloud-init can rename them, producing
`[busy] Error renaming` and leaving DHCP in place. Check `cloud-init status
--long`, `ip -br address` and `/etc/netplan/50-cloud-init.yaml` on each VM.
Updating a VM's cloud-init configuration does not rerun networking on its
existing root disk. For disposable, not-yet-bootstrapped VMs, review a
replacement plan for the four `harvester_virtualmachine.nodes` resources;
replacement deletes their root disks. Do not replace a server containing an
existing etcd cluster without a backup and recovery plan. Alternatively,
repair networking from each VM's console after backing up its configuration;
applying network changes can disconnect SSH. Remove any obsolete
`^primary0$` override from tfvars before retrying Terraform.

## Lifecycle and security

- Terraform state and `.bootstrap` contain the join token and generated scripts;
  the kubeconfig grants cluster-admin access. Protect them and use encrypted,
  access-controlled remote state for shared usage. Local generated files are
  ignored by Git; custom paths require their own protection.
- Editing the pool or interface reruns the configuration step. Changing a pool
  may reassign service IPs; check the pool for conflicts and coordinate changes.
- Changing RKE2 version, Cilium chart values, cloud-init or node networking
  does **not** upgrade or reconfigure existing nodes. Follow supported RKE2
  upgrade procedures and manage core HelmChartConfig changes deliberately.
  Cloud-init network changes normally require VM replacement.
- Harvester provider 1.8.0 can report a perpetual in-place removal of the
  auto-generated `cloudinitdisk` after refresh. See
  [Harvester issue 10728](https://github.com/harvester/harvester/issues/10728);
  review plans rather than assuming this represents an intended disk change.
- Do not blindly replace the only server: it holds etcd and the cluster's
  endpoint. Back up etcd snapshots and the RKE2 token off-cluster and follow
  RKE2 recovery instructions. A fresh server initializes a new cluster.
- `terraform destroy` removes the VMs and their disks and the namespace. It
  does not remove local kubeconfig or `.bootstrap` credentials.

## Offline checks

```sh
terraform init -backend=false
terraform validate
terraform test
helm lint apps/charts/cluster-issuer
helm lint apps/charts/traefik-ip-pool
bash -n scripts/cluster.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_*.py' -v
```

References: [RKE2 CNI configuration](https://docs.rke2.io/networking/basic_network_options),
[Cilium L2 announcements](https://docs.cilium.io/en/stable/network/l2-announcements/),
[Cilium LB IPAM](https://docs.cilium.io/en/stable/network/lb-ipam/), and
[Cilium BGP control plane](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane/).
