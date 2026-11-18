resource "proxmox_virtual_environment_vm" "test_vm" {
  for_each = var.vms

  name      = each.key
  node_name = each.value.node

  lifecycle {
      ignore_changes = [
        initialization[0].user_account,
      ]
    }

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  agent {
    enabled = true
    timeout = "10s" 
  }
  cpu {
    cores = each.value.cores
    type = each.value.type
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_size
  }
  
  network_device {
    bridge = "vmbr0"
    model  = "virtio"
  }

  vga {
    type = "serial0"
  }
#Cloud-init configuration for the VM. This is where I set the static IP and gateway for the VM. 
#Documentation: https://registry.terraform.io/providers/bpg/proxmox/latest/docs/guides/cloud-init
  initialization {
    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = each.value.gateway
      }
    }
    user_account {
    username = "ansible"
    keys = [trimspace(var.ssh_public_key)]
    
  }
  }
}
resource "proxmox_virtual_environment_container" "monitoring" {
  node_name = "proxmox"
  vm_id     = 201

  clone {
        vm_id = 200
      }
      
  unprivileged = true
  features {
    nesting = true
  }

  initialization {
    hostname = "monitoring-01"

    ip_config {
      ipv4 {
        address = "192.168.1.170/24"
        gateway = "192.168.1.1"
      }
    }

    
  }
  started = true
}

# Cloudflare tunnel configuration for the monitoring container. 

resource "cloudflare_zero_trust_tunnel_cloudflared" "portfolio_tunnel" {
  account_id = var.cloudflare_account_id
  name       = "homelab"
  config_src = "cloudflare"
}

resource "cloudflare_dns_record" "portfolio_dns" {
  zone_id = var.cloudflare_zone_id
  name    = "h-w.cloud"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.portfolio_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "portfolio_www_dns" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.portfolio_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "n8n" {
  zone_id = var.cloudflare_zone_id
  name    = "n8n"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.portfolio_tunnel.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "fluxer_dns" {
  zone_id = var.cloudflare_zone_id
  name    = "chat"
  content = "31.21.30.230"
  type    = "A"
  proxied = true
  ttl     = 1
}

locals {
  tunnel_hostnames = [
    "h-w.cloud",
    "www.h-w.cloud",
    "n8n.h-w.cloud",
  ]
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "portfolio_tunnel_config" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.portfolio_tunnel.id

  config = {
    ingress = concat(
      [for hostname in local.tunnel_hostnames : {
        hostname = hostname
        service  = "http://traefik:80"
      }],
      [{
        service = "http_status:404"
      }]
    )
  }
}