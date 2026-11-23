mock_provider "harvester" {}
mock_provider "kubernetes" {}
mock_provider "kubernetes" {
  alias = "cluster"
}
mock_provider "helm" {}
mock_provider "local" {}
mock_provider "random" {}

variables {
  namespace                = "test-cluster"
  image_id                 = "default/ubuntu"
  vm_ssh_public_key        = "ssh-ed25519 test-only"
  nic1_gateway             = "192.0.2.1"
  nic1_dns_servers         = ["192.0.2.1"]
  master_nic1_cidr         = "192.0.2.10/24"
  master_nic2_cidr         = "198.51.100.10/24"
  worker_nic1_cidrs        = ["192.0.2.11/24", "192.0.2.12/24", "192.0.2.13/24"]
  worker_nic2_cidrs        = ["198.51.100.11/24", "198.51.100.12/24", "198.51.100.13/24"]
  load_balancer_ip_range   = { start = "192.0.2.200", stop = "192.0.2.220" }
  traefik_load_balancer_ip = "192.0.2.205"
}

run "application_stack" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.traefik.values[0]).service.spec.type == "LoadBalancer" && yamldecode(helm_release.traefik.values[0]).service.spec.externalTrafficPolicy == "Cluster" && yamldecode(helm_release.traefik.values[0]).service.annotations["lbipam.cilium.io/ips"] == "192.0.2.205" && length(helm_release.traefik_ip_pool) == 0
    error_message = "Traefik must use a Cilium-compatible LoadBalancer Service."
  }
  assert {
    condition     = yamldecode(helm_release.traefik.values[0]).ingressClass.isDefaultClass && yamldecode(helm_release.traefik.values[0]).ports.web.http.redirections.entryPoint.to == "websecure"
    error_message = "Traefik must be the default ingress and redirect HTTP to HTTPS."
  }
  assert {
    condition     = yamldecode(helm_release.monitoring.values[0]).grafana.ingress.hosts == ["grafana.192.0.2.205.nip.io"] && yamldecode(helm_release.monitoring.values[0]).grafana.ingress.annotations["cert-manager.io/cluster-issuer"] == "selfsigned" && yamldecode(helm_release.monitoring.values[0]).grafana.ingress.tls[0].hosts == ["grafana.192.0.2.205.nip.io"]
    error_message = "Grafana ingress must use the configured hostname and self-signed TLS issuer."
  }
  assert {
    condition     = !yamldecode(helm_release.monitoring.values[0]).grafana.persistence.enabled && !yamldecode(helm_release.monitoring.values[0]).kubeProxy.enabled && !yamldecode(helm_release.monitoring.values[0]).kubeEtcd.enabled
    error_message = "Monitoring must not require storage or scrape kube-proxy or unavailable control-plane metrics."
  }
  assert {
    condition     = yamldecode(helm_release.monitoring.values[0]).grafana.admin.existingSecret == "grafana-admin"
    error_message = "Grafana must get its generated administrator credentials from the Kubernetes secret."
  }
}

run "custom_grafana_host" {
  command = plan
  variables {
    grafana_host = "monitor.lab.example.com"
  }
  assert {
    condition     = yamldecode(helm_release.monitoring.values[0]).grafana.ingress.hosts == ["monitor.lab.example.com"] && output.grafana_url == "https://monitor.lab.example.com"
    error_message = "The Grafana hostname override must reach the ingress and URL output."
  }
}

run "outside_pool" {
  command = plan
  variables {
    traefik_load_balancer_ip = "192.0.2.221"
  }
  assert {
    condition     = length(helm_release.traefik_ip_pool) == 1 && yamldecode(helm_release.traefik_ip_pool[0].values[0]).ip == "192.0.2.221"
    error_message = "An out-of-pool static IP must get a dedicated Traefik pool."
  }
}

run "automatic_traefik_ip" {
  command = plan
  variables {
    traefik_load_balancer_ip = null
  }
  assert {
    condition     = length(helm_release.traefik_ip_pool) == 0 && length(yamldecode(helm_release.traefik.values[0]).service.annotations) == 0
    error_message = "Automatic allocation must not request a specific IP or create a dedicated pool."
  }
}

run "missing_domain" {
  command = plan
  variables {
    domain = null
  }
  expect_failures = [var.domain]
}
