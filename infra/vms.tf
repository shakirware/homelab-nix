locals {
  vms_regular = { for k, v in var.vms : k => v if k != "vm-storage" }
  vms_storage = { for k, v in var.vms : k => v if k == "vm-storage" }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms_regular

  name            = each.key
  node_name       = local.node_name
  vm_id           = each.value.vmid
  pool_id         = local.pool_id
  machine         = each.value.machine
  keyboard_layout = each.value.keyboard_layout
  description     = each.value.description
  scsi_hardware   = each.value.scsi_hardware

  started             = true
  on_boot             = true
  stop_on_destroy     = true
  reboot_after_update = false

  boot_order = each.value.boot_order

  clone {
    vm_id = local.template_vmid
    full  = true
  }

  agent {
    enabled = true
    type    = "virtio"
    timeout = "15m"
  }

  initialization {
    datastore_id = local.datastore_id
    interface    = "ide2"
    upgrade      = true

    dynamic "user_account" {
      for_each = each.value.cloud_init_user == null ? [] : [each.value.cloud_init_user]
      content {
        username = user_account.value
      }
    }
  }

  operating_system { type = "l26" }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  dynamic "disk" {
    for_each = each.value.extra_disks
    content {
      # A host block device has no Proxmox storage backend.  An explicit empty
      # value prevents the provider defaulting this to local-lvm.
      datastore_id      = ""
      interface         = disk.value.interface
      path_in_datastore = disk.value.path_in_datastore
      backup            = disk.value.backup
      discard           = disk.value.discard
      ssd               = disk.value.ssd
    }
  }

  disk {
    datastore_id = local.datastore_id
    interface    = "virtio0"
    size         = each.value.disk_size_gb
    file_format  = "raw"
    discard      = each.value.root_discard
  }

  dynamic "network_device" {
    for_each = { for idx, nic in each.value.nics : idx => nic }
    content {
      bridge      = network_device.value.bridge
      model       = "virtio"
      mac_address = network_device.value.mac
      vlan_id     = network_device.value.vlan_id
    }
  }

  dynamic "hostpci" {
    for_each = each.key == "vm-media" ? [1] : []
    content {
      device  = "hostpci0"
      mapping = proxmox_virtual_environment_hardware_mapping_pci.igpu.name
      pcie    = true
      rombar  = false
      xvga    = false
    }
  }

  dynamic "serial_device" {
    for_each = each.value.serial_console ? [1] : []
    content {
      device = "socket"
    }
  }

  lifecycle {
    ignore_changes = [clone, description]
  }
}

resource "proxmox_virtual_environment_vm" "vm_storage" {
  for_each = local.vms_storage

  name            = each.key
  node_name       = local.node_name
  vm_id           = each.value.vmid
  pool_id         = local.pool_id
  machine         = each.value.machine
  keyboard_layout = each.value.keyboard_layout
  description     = each.value.description
  scsi_hardware   = each.value.scsi_hardware

  started             = true
  on_boot             = true
  stop_on_destroy     = true
  reboot_after_update = false

  boot_order = each.value.boot_order

  clone {
    vm_id = local.template_vmid
    full  = true
  }

  agent {
    enabled = true
    type    = "virtio"
    timeout = "15m"
  }

  initialization {
    datastore_id = local.datastore_id
    interface    = "ide2"
    upgrade      = true
  }

  operating_system { type = "l26" }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  dynamic "disk" {
    for_each = each.value.extra_disks
    content {
      # A host block device has no Proxmox storage backend.  An explicit empty
      # value prevents the provider defaulting this to local-lvm.
      datastore_id      = ""
      interface         = disk.value.interface
      path_in_datastore = disk.value.path_in_datastore
      backup            = disk.value.backup
      discard           = disk.value.discard
      ssd               = disk.value.ssd
    }
  }

  disk {
    datastore_id = local.datastore_id
    interface    = "virtio0"
    size         = each.value.disk_size_gb
    file_format  = "raw"
    discard      = each.value.root_discard
  }

  dynamic "network_device" {
    for_each = { for idx, nic in each.value.nics : idx => nic }
    content {
      bridge      = network_device.value.bridge
      model       = "virtio"
      mac_address = network_device.value.mac
      vlan_id     = network_device.value.vlan_id
    }
  }

  lifecycle {
    ignore_changes = [clone, description]
  }
}
