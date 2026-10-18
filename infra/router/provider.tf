variable "routeros_url" {
  type        = string
  default     = "https://192.168.1.1"
  description = "RouterOS REST API (www-ssl, admin workstation only)"
}

variable "routeros_username" {
  type        = string
  default     = "tofu"
  description = "RouterOS user for OpenTofu (group iac, bootstrap.rsc)"
}

variable "routeros_password" {
  type        = string
  sensitive   = true
  description = "TF_VAR_routeros_password in secrets/env.yaml"
}

provider "routeros" {
  hosturl  = var.routeros_url
  username = var.routeros_username
  password = var.routeros_password
  # The router's own CA (bootstrap.rsc).
  ca_certificate = "${path.module}/router-ca.crt"
}
