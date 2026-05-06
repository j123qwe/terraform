# RKE2 Kubernetes Cluster Deployment

Enterprise-grade high-availability RKE2 Kubernetes cluster deployed with Ansible. This setup provides a production-ready cluster with Cilium CNI, kube-proxy replacement via eBPF datapath, Hubble observability, and SCTP support.

## 🏗️ Architecture Overview

- **Control Plane**: 3-node HA setup with embedded etcd
- **Worker Nodes**: 3+ agent nodes for workload distribution
- **CNI**: Cilium with eBPF datapath (kube-proxy disabled)
- **Ingress**: Traefik omitted from RKE2 install (deploy separately)
- **Storage**: Local storage or external CSI drivers
- **Load Balancing**: External load balancer recommended for production

## 📁 Directory Structure

```
rke2/
├── ansible.cfg                    # Ansible configuration
├── README.md                      # This file
├── cluster/                       # Cluster-specific configurations
│   ├── template/                  # 🎯 Template cluster for new deployments
│   │   ├── hosts                  # Inventory file with node definitions
│   │   └── group_vars/
│   │       ├── all.yml           # Cluster-wide configuration
│   │       └── agent.yml         # Worker node specific settings
│   └── lochiciloam/              # Example production cluster
│       ├── hosts
│       └── group_vars/
├── playbooks/                     # Ansible playbooks
│   ├── deploy.yml                # Main deployment playbook
│   ├── reset.yml                 # ⚠️  Destructive cluster reset
│   └── README.md                 # Playbook documentation
└── roles/                        # Ansible roles
    ├── prereq/                   # System prerequisites
    ├── rke2_server/              # Control plane setup
    └── rke2_agent/               # Worker node setup
```

## 🚀 Quick Start (Template Cluster)

### 1. Prerequisites

**System Requirements:**
- **OS**: Ubuntu 20.04+ / RHEL 8+ / Rocky Linux 8+
- **Memory**: 4GB+ for servers, 2GB+ for agents
- **CPU**: 2+ cores per node
- **Network**: All nodes must communicate on ports 6443, 9345, 10250
- **DNS**: `cluster_fqdn` must resolve to first server IP or load balancer

**Ansible Requirements:**
```bash
# Install required collections
ansible-galaxy collection install community.general ansible.posix

# Verify Ansible version (2.14+)
ansible --version
```

### 2. Configure Your Cluster

**Copy and customize the template:**
```bash
cd /rke2
cp -r cluster/template cluster/my-cluster
```

**Edit the inventory file:**
```
bash vi cluster/my-cluster/hosts
```

**Template inventory structure:**
```ini
[server]
rke2-mn01 ansible_host=192.168.86.204 
rke2-mn02 ansible_host=192.168.86.205 
rke2-mn03 ansible_host=192.168.86.206 

[agent]
rke2-wn01 ansible_host=192.168.86.214 
rke2-wn02 ansible_host=192.168.86.215 
rke2-wn03 ansible_host=192.168.86.216 

[k3s_cluster:children]
server
agent
```

**Configure cluster settings:**
```bash
vi cluster/my-cluster/group_vars/all.yml
```

### 3. Deploy the Cluster

```bash
cd /home/syseng/Interlink_K8s/rke2
ansible-playbook -i cluster/my-cluster/ playbooks/deploy.yml
```

### 4. Access Your Cluster

The kubeconfig is automatically downloaded to `~/.kube/rke2-domain.yaml` (configurable):

```bash
export KUBECONFIG=~/.kube/rke2-domain.yaml
kubectl get nodes
kubectl get pods -A
```

## ⚙️ Configuration Reference

### Core Variables (`group_vars/all.yml`)

| Variable | Default | Description |
|----------|---------|-------------|
| `rke2_version` | `v1.32.3+rke2r1` | RKE2 release version ([releases](https://github.com/rancher/rke2/releases)) |
| `rke2_token` | *(random string)* | **🔐 CHANGE THIS!** Shared secret for node authentication |
| `cluster_fqdn` | `rke2-cluster.domain.com` | **🌐 DNS required** - API server endpoint |
| `cilium_k8s_host` | `rke2-cluster.domain.com` | Cilium API server override (IP if DNS not ready) |
| `cluster_context` | `rke2-domain` | Kubectl context name |

### Network Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `api_port` | `6443` | Kubernetes API server port |
| `registration_port` | `9345` | RKE2 supervisor port (node registration) |
| `cluster_cidr` | `10.42.0.0/16` | Pod network CIDR |
| `service_cidr` | `10.43.0.0/16` | Service network CIDR |
| `mgmt_interface` | `ens160` | Management network interface |
| `traffic_interface` | `ens192` | Cilium dataplane interface |

### Node Labels (`group_vars/agent.yml`)

```yaml
node_labels:
  - "nodeType=worker"
  - "environment=production"
  - "zone=us-west-1a"
```

## 🏛️ Template Cluster Deep Dive

The **template cluster** serves as the reference implementation for new RKE2 deployments. Here's what makes it special:

### Network Architecture
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Server 1      │    │   Server 2      │    │   Server 3      │
│ 192.168.86.204  │◄──►│ 192.168.86.205  │◄──►│ 192.168.86.206  │
│ (Bootstrap)     │    │                 │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
    ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
    │   Worker 1      │    │   Worker 2      │    │   Worker 3      │
    │ 192.168.86.214  │    │ 192.168.86.215  │    │ 192.168.86.216  │
    └─────────────────┘    └─────────────────┘    └─────────────────┘
```

### Key Features
- **Bootstrap Node**: `rke2-mn01` initializes the etcd cluster
- **Join Process**: Subsequent servers join via supervisor port 9345
- **Load Distribution**: Workers connect to any available server
- **Network Segmentation**: Separate management and traffic interfaces

### Security Hardening
```yaml
# TLS SANs include all access points
tls-san:
  - "rke2-cluster.domain.com"    # Primary FQDN
  - "192.168.86.204"             # Individual server IPs
  - "192.168.86.205"
  - "192.168.86.206"
```

## 🔧 Customizing for Production

### 1. Update Network Settings
```yaml
# Adjust for your network
cluster_cidr: "10.42.0.0/16"      # Avoid conflicts with existing networks
service_cidr: "10.43.0.0/16"
mgmt_interface: "ens160"           # Check with: ip link show
traffic_interface: "ens192"
```

### 2. Generate Secure Token
```bash
# Generate a secure cluster token
openssl rand -base64 64
```

### 3. Set Up DNS
```dns
rke2-cluster.domain.com.    IN    A    192.168.86.204
                           IN    A    192.168.86.205  
                           IN    A    192.168.86.206
```

### 4. Firewall Configuration
**Required Ports:**
- `6443/tcp` - Kubernetes API server
- `9345/tcp` - RKE2 supervisor port
- `10250/tcp` - Kubelet API
- `2379-2380/tcp` - etcd (server nodes only)
- `30000-32767/tcp` - NodePort range (optional)

## 🚨 Cluster Reset (Destructive)

**⚠️ WARNING**: This completely destroys the cluster and all data!

```bash
cd /home/syseng/Interlink_K8s/rke2
ansible-playbook -i cluster/my-cluster/ playbooks/reset.yml
```

The reset playbook:
- Stops all RKE2 services
- Removes all configuration and data
- Cleans network interfaces and iptables
- Reboots all nodes for clean state
- Requires typing "DESTROY" to confirm

## 🔍 Troubleshooting

### Common Issues

**DNS Resolution Problems:**
```bash
# Test from any node
nslookup rke2-cluster.domain.com

# Temporary workaround - set IP directly
cilium_k8s_host: "192.168.86.204"
```

**Node Not Ready:**
```bash
# Check node status
kubectl describe node <node-name>

# Check Cilium pods
kubectl get pods -n kube-system -l k8s-app=cilium
```

**Certificate Errors:**
```bash
# Verify TLS SANs include your access method
kubectl config view --raw | grep server:
```

### Ansible Debugging
```bash
# Increase verbosity
ansible-playbook -vvv -i cluster/my-cluster/ playbooks/deploy.yml

# Check specific node
ansible -i cluster/my-cluster/ rke2-mn01 -m ping
```

## 📚 Additional Resources

- **RKE2 Documentation**: https://docs.rke2.io/
- **Cilium Documentation**: https://docs.cilium.io/
- **Kubernetes Documentation**: https://kubernetes.io/docs/
- **Cluster Upgrades**: Follow RKE2 upgrade procedures
- **Backup Strategy**: Implement etcd backup procedures

## 🔄 Cluster Management

### Adding Nodes
1. Update inventory file with new nodes
2. Run deployment with `--limit new_nodes`
3. Verify node joins cluster successfully

### Removing Nodes  
1. Drain workloads: `kubectl drain <node> --ignore-daemonsets`
2. Remove from cluster: `kubectl delete node <node>`
3. Run reset playbook on specific node: `--limit <node>`

### Version Upgrades
1. Update `rke2_version` in `group_vars/all.yml`
2. Run deployment playbook (rolling upgrade)
3. Verify cluster health post-upgrade

---
**Template Cluster Status**: ✅ Production Ready | 🔧 Customizable | 📖 Well Documented
| `cluster_context` | `rke2-domain` | kubeconfig context name |
| `api_port` | `6443` | Kubernetes API port |
| `registration_port` | `9345` | RKE2 supervisor/join port |
| `cluster_cidr` | `10.42.0.0/16` | Pod network |
| `service_cidr` | `10.43.0.0/16` | Service network |
| `mgmt_interface` | `eth0` | Management NIC — K8s API, etcd, node registration |
| `traffic_interface` | `eth1` | Data plane NIC — pod-to-pod and NodePort traffic |
| `kubeconfig` | `~/.kube/rke2-domain.yaml` | Written to the Ansible control node |

Adjust `mgmt_interface` and `traffic_interface` to match your OS interface names (`ip link show`).

## Deployment

### Fresh cluster

```bash
ansible-playbook playbooks/deploy.yml
```

The playbook runs in three serial phases:

1. **prereq** — all nodes: kernel modules, sysctl, package deps, firewall ports
2. **rke2_server** — servers one at a time (`serial: 1`): first server initialises with `cluster-init: true`; subsequent servers join via the first server's supervisor port
3. **rke2_agent** — all agents in parallel: slurps the join token from the first server's filesystem, installs and registers

### Add new nodes

Just add the node to `inventory.ini` and re-run `deploy.yml`. The playbook is idempotent:

- Existing nodes skip the install (version already satisfied), skip config writes (no diff), and skip service restarts.
- New nodes install, configure, and join automatically.

No separate playbook is needed. This works for both new agents and new server nodes. The join token is always read directly from `/var/lib/rancher/rke2/server/node-token` on the first server via Ansible delegation, so the agent and joining-server roles are self-contained even when run with `--limit`.

```bash
# Add rke2-wn04 to [agent] in inventory.ini, then:
ansible-playbook playbooks/deploy.yml
# or target only the new node (token is fetched live from the first server):
ansible-playbook playbooks/deploy.yml --limit rke2-wn04
```

### kubeconfig

After deployment the kubeconfig is written to `~/.kube/rke2-domain.yaml` on the Ansible control node with the context renamed to `rke2-domain` and the server address set to `https://rke2-cluster.domain.com:6443`.

```bash
export KUBECONFIG=~/.kube/rke2-domain.yaml
kubectl get nodes
```

On the server nodes themselves it is at `~/.kube/config`.

## Cilium

Cilium is deployed by RKE2's built-in Helm controller. The configuration lives in:

```
roles/rke2_server/templates/rke2-cilium-config.yaml.j2
```

This renders to `/var/lib/rancher/rke2/server/manifests/rke2-cilium-config.yaml` on the first server before the service starts, so RKE2 picks it up on first boot. Changes to it trigger an automatic Helm upgrade of the `rke2-cilium` release.

### What is enabled

| Feature | Setting |
|---|---|
| kube-proxy replacement | `kubeProxyReplacement: true` |
| SCTP | `sctp.enabled: true` |
| Hubble | `hubble.enabled: true` |
| Hubble relay | `hubble.relay.enabled: true` |
| Hubble UI | `hubble.ui.enabled: true` |
| Tunnel mode | VXLAN (default) |

### Dual-interface setup

Cilium attaches its eBPF programs to both `mgmt_interface` and `traffic_interface`. NodePort traffic is directed to `traffic_interface` so external service traffic does not traverse the management NIC.

```yaml
devices:
  - eth0   # mgmt_interface
  - eth1   # traffic_interface

nodePort:
  directRoutingDevice: eth1
```

**Native routing (optional):** If your traffic network has full L2 adjacency between all nodes, you can switch to zero-overhead direct routing by replacing the tunnel settings in the Cilium template with:

```yaml
routingMode: native
autoDirectNodeRoutes: true
ipv4NativeRoutingCIDR: "10.42.0.0/16"
```

## Server node taints

Server nodes are tainted with `CriticalAddonsOnly=true:NoExecute`, which prevents user workloads from being scheduled on control plane nodes. Only pods that carry the `CriticalAddonsOnly` toleration will run there — this includes all RKE2 system daemonsets (Cilium, CoreDNS, etc.) which have it by default.

See the [RKE2 HA docs](https://docs.rke2.io/install/ha#2a-optional-consider-server-node-taints) for background.

**On a fresh cluster** the taint is applied at first boot before any workloads are scheduled.

**On an existing cluster** re-running the playbook will update the config and restart the server service, applying the taint. Any user pods already running on server nodes will be evicted.

**To run a specific pod on a server node** (e.g. a debugging pod), add the toleration explicitly:

```yaml
tolerations:
  - key: CriticalAddonsOnly
    operator: Exists
```

## Ingress

`rke2-ingress-nginx` is disabled in the RKE2 server config. Deploy Traefik from `../k8s/ingress/` after the cluster is up. The existing Helm values and manifests are compatible with RKE2.

## RKE2 paths reference

| Path | Purpose |
|---|---|
| `/etc/rancher/rke2/config.yaml` | Node configuration |
| `/var/lib/rancher/rke2/server/manifests/` | Auto-applied Helm charts and manifests |
| `/var/lib/rancher/rke2/server/node-token` | Join token |
| `/etc/rancher/rke2/rke2.yaml` | Cluster kubeconfig |
| `/var/lib/rancher/rke2/bin/kubectl` | Bundled kubectl (add to PATH via `.bashrc`) |
| `journalctl -u rke2-server -f` | Server logs |
| `journalctl -u rke2-agent -f` | Agent logs |
