variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API URL"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Terraform API token from Proxmox"
}
#Variables for VM configuration. Default values are set because it's the baseline for a test VM, can be overwritten.
variable "vms"{
  type = map(object({
    node      = string
    ip        = string
    gateway   = string
    cores     = number
    memory    = number
    disk_size = optional(number, 3) #Optional disk size variable with a default value of 3GB
  }))
  description = "Map of VM configurations"
}

variable "template_vm_id" {
  type        = number
  description = "VM ID of the template to clone"
  default     = 9000
}

variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "Cloudflare API token for managing DNS records and tunnels."
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID for managing DNS records and tunnels."
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone ID for managing DNS records."
}
