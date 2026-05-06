# RKE2 Playbooks

This directory contains Ansible playbooks for managing RKE2 Kubernetes clusters.

### deploy.yml - Cluster Deployment
**Purpose**: Deploys a complete RKE2 high-availability cluster with servers and agents.

**Features**:
- Sequential server deployment (bootstrap → join)
- Parallel agent deployment
- Automatic kubeconfig retrieval
- Cilium CNI with eBPF datapath
- Node readiness verification

**Usage**:
```bash
cd /home/syseng/Interlink_K8s/rke2
ansible-playbook -i cluster/template/ playbooks/deploy.yml
ansible-playbook -i cluster/lochiciloam/ playbooks/deploy.yml
```

**Process Flow**:
1. **Prerequisites**: System setup, kernel modules, firewall
2. **Bootstrap**: First server initializes etcd cluster  
3. **Join Servers**: Remaining servers join via supervisor port
4. **Deploy Agents**: Worker nodes join in parallel
5. **Verification**: Nodes become Ready, kubeconfig retrieved

---

### reset.yml - Complete Cluster Destruction
**⚠️ CRITICAL WARNING - DESTRUCTIVE OPERATION ⚠️**

**Purpose**: Completely removes all RKE2 components from cluster nodes and reboots for clean state.

**Safety Features**:
- **Double confirmation required**: Must type "DESTROY" exactly
- **Detailed warning prompt**: Shows exactly what will be destroyed
- **Immediate failure**: Playbook stops if confirmation doesn't match
- **Parallel execution**: All nodes reset simultaneously for speed

**What Gets Destroyed**:
- ✅ **Services**: All RKE2 systemd services stopped and disabled
- ✅ **Processes**: All Kubernetes and container runtime processes killed
- ✅ **Filesystems**: All RKE2 mount points unmounted
- ✅ **Binaries**: `/usr/local/bin/rke2` and all related tools removed
- ✅ **Configuration**: `/etc/rancher/rke2/` completely wiped
- ✅ **Data**: `/var/lib/rancher/rke2/` and `/var/lib/kubelet/` destroyed
- ✅ **Container Runtime**: containerd data and images deleted
- ✅ **Network**: CNI interfaces, namespaces, and iptables rules cleaned
- ✅ **Services**: systemd service files removed and daemon reloaded
- ✅ **System State**: All nodes rebooted for guaranteed clean slate

**Usage**:
```bash
cd /home/syseng/Interlink_K8s/rke2
ansible-playbook -i cluster/my-cluster/ playbooks/reset.yml
```

**Interactive Flow**:
```
Enter the Ansible username: admin
Enter the Ansible password: [hidden]

⚠️  WARNING: This will COMPLETELY DESTROY the RKE2 cluster and ALL DATA! ⚠️

This action will:
- Stop all RKE2 services
- Delete all Kubernetes data and configurations
- Remove all container images and volumes
- Wipe network configurations
- Reboot all nodes

Type 'DESTROY' (all caps) to confirm: DESTROY

[Proceeds with destruction...]
```

**Post-Reset State**:
- Nodes are rebooted and completely clean
- No trace of RKE2 installation remains
- Ready for fresh deployment with `deploy.yml`
- All networking returned to pre-RKE2 state

---

## 🔧 Playbook Execution Tips

### Using Different Inventories
```bash
# Template cluster (for testing/development)
ansible-playbook -i cluster/template/ playbooks/deploy.yml

# Production cluster
ansible-playbook -i cluster/production/ playbooks/deploy.yml

# Staging environment
ansible-playbook -i cluster/staging/ playbooks/deploy.yml
```

### Limiting to Specific Nodes
```bash
# Deploy only to new worker nodes
ansible-playbook -i cluster/my-cluster/ playbooks/deploy.yml --limit agent

# Reset only specific nodes
ansible-playbook -i cluster/my-cluster/ playbooks/reset.yml --limit rke2-wn01

# Deploy new server to existing cluster
ansible-playbook -i cluster/my-cluster/ playbooks/deploy.yml --limit rke2-mn04
```

### Debugging and Verbosity
```bash
# High verbosity for troubleshooting
ansible-playbook -vvv -i cluster/my-cluster/ playbooks/deploy.yml

# Check syntax without execution
ansible-playbook --syntax-check -i cluster/my-cluster/ playbooks/deploy.yml

# Dry run (check mode)
ansible-playbook --check -i cluster/my-cluster/ playbooks/deploy.yml
```

## ⚡ Performance Characteristics

### Deployment Times (Typical)
- **3-node cluster**: ~8-12 minutes
- **6-node cluster**: ~10-15 minutes  
- **12-node cluster**: ~12-18 minutes

### Reset Times (Parallel)
- **Any size cluster**: ~3-5 minutes (all nodes simultaneously)
- **Network cleanup**: ~1-2 minutes additional
- **Reboot cycle**: ~2-3 minutes (depends on hardware)

## 🛡️ Safety and Best Practices

### Before Deployment
1. ✅ Verify DNS resolution for `cluster_fqdn`
2. ✅ Ensure all nodes accessible via SSH
3. ✅ Check firewall ports (6443, 9345, 10250)
4. ✅ Validate inventory file syntax
5. ✅ Test with `--check` mode first

### Before Reset
1. 🚨 **BACKUP ALL DATA** - This cannot be undone!
2. 🚨 Drain workloads if partial reset needed
3. 🚨 Coordinate with team - affects entire cluster
4. 🚨 Verify you have the correct inventory file
5. 🚨 Double-check cluster identity before proceeding

### Post-Operations
- **After Deploy**: Verify cluster access, check node status
- **After Reset**: Confirm clean state, validate network connectivity

---

## 📖 Related Documentation

- **Main README**: `../README.md` - Complete RKE2 setup guide
- **Template Cluster**: `../cluster/template/` - Reference configuration  
- **Configuration Guide**: Variable explanations and networking setup
- **Troubleshooting**: Common issues and debugging steps