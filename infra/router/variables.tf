variable "trusted_ssid" {
  type        = string
  description = "SSID of the trusted network on VLAN 1 (site.private.auto.tfvars)"
}

variable "trusted_wifi_passphrase" {
  type        = string
  sensitive   = true
  description = "Trusted SSID passphrase (TF_VAR_trusted_wifi_passphrase in secrets/env.yaml)"

  validation {
    condition     = length(var.trusted_wifi_passphrase) >= 20
    error_message = "Use at least 20 characters."
  }
}

variable "iot_reservations" {
  description = <<-EOT
    Fixed IoT addresses keyed by device name (site.private.auto.tfvars).
    role: apple_tv | tv | hub | iot. Apple TVs and TVs get the AirPlay return
    and direct media rules.
  EOT
  type = map(object({
    mac     = string
    ip      = string
    role    = string
    comment = optional(string, "")
  }))

  validation {
    condition     = alltrue([for r in values(var.iot_reservations) : contains(["apple_tv", "tv", "hub", "iot"], r.role)])
    error_message = "role must be apple_tv, tv, hub or iot."
  }

  validation {
    condition     = alltrue([for r in values(var.iot_reservations) : can(regex("^192\\.168\\.40\\.([2-9]|[1-9][0-9])$", r.ip))])
    error_message = "Reservations use 192.168.40.2-99; the dynamic pool is .100-.199."
  }
}
