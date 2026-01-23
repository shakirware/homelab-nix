resource "proxmox_virtual_environment_hardware_mapping_pci" "igpu" {
  name    = "igpu"
  comment = "Intel UHD 630 at 0000:00:02.0"

  map = [{
    node         = local.node_name
    path         = "0000:00:02.0"
    id           = "8086:3e91"
    subsystem_id = "1043:8694"
    iommu_group  = 0
  }]
}
