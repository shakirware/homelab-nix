variable "vms" {
  type = map(object({
    vmid         = number
    cores        = number
    memory       = number
    disk_size_gb = number
    nics = list(object({
      bridge = string
      mac    = string
    }))
  }))

  validation {
    condition     = length(distinct([for v in values(var.vms) : v.vmid])) == length(values(var.vms))
    error_message = "Each VM must have a unique vmid (duplicate vmid found)."
  }

  validation {
    condition     = alltrue([for v in values(var.vms) : (v.vmid >= 100 && v.vmid <= 999999)])
    error_message = "Each vmid must be in range [100, 999999]."
  }

  validation {
    condition     = alltrue([for v in values(var.vms) : (v.cores > 0 && v.memory >= 512 && v.disk_size_gb > 0)])
    error_message = "Each VM must have cores > 0, memory >= 512 (MB), and disk_size_gb > 0."
  }

  validation {
    condition     = alltrue([for v in values(var.vms) : (length(v.nics) > 0)])
    error_message = "Each VM must define at least one NIC in vms[*].nics."
  }

  validation {
    condition     = alltrue([for v in values(var.vms) : alltrue([for nic in v.nics : can(regex("^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$", nic.mac))])])
    error_message = "All NIC MAC addresses must be in format aa:bb:cc:dd:ee:ff."
  }
}

locals {
  node_name     = "pve"
  template_vmid = 9000
  pool_id       = "homelab"
  datastore_id  = "local-lvm"
}
