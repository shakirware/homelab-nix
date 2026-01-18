variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token"
}

variable "proxmox_insecure" {
  type        = bool
  default     = false
  description = "Disable TLS"
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = var.proxmox_insecure
}
