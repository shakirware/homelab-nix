locals {
  vms_regular = { for k, v in var.vms : k => v if k != "vm-storage" }
  vms_storage = { for k, v in var.vms : k => v if k == "vm-storage" }
}

resource "proxmox_virtual_environment_vm" "vm" {
  for_each = local.vms_regular

  name      = each.key
  node_name = local.node_name
  vm_id     = each.value.vmid
  pool_id   = local.pool_id

  machine = "q35"

  started         = true
  on_boot         = true
  stop_on_destroy = true

  boot_order = ["virtio0", "net0"]

  clone {
    vm_id = local.template_vmid
    full  = true
  }

  agent {
    enabled = true
    type    = "virtio"
    timeout = "30s"
  }

  initialization {
    datastore_id = local.datastore_id
    interface    = "ide2"
    upgrade      = false
  }

  operating_system { type = "l26" }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  # Keep a virtual display so the Proxmox Console tab works
  vga {
    memory = 16
  }

  disk {
    datastore_id = local.datastore_id
    interface    = "virtio0"
    size         = each.value.disk_size_gb
    file_format  = "raw"
    discard      = "on"
  }

  dynamic "network_device" {
    for_each = { for idx, nic in each.value.nics : idx => nic }
    content {
      bridge      = network_device.value.bridge
      model       = "virtio"
      mac_address = network_device.value.mac
    }
  }

  dynamic "hostpci" {
    for_each = each.key == "vm-media" ? [1] : []
    content {
      device  = "hostpci0"
      mapping = proxmox_virtual_environment_hardware_mapping_pci.igpu.name
      pcie    = true
    }
  }


  lifecycle {
    ignore_changes = [clone]
  }
}

resource "proxmox_virtual_environment_vm" "vm_storage" {
  for_each = local.vms_storage

  name      = each.key
  node_name = local.node_name
  vm_id     = each.value.vmid
  pool_id   = local.pool_id

  started         = true
  on_boot         = true
  stop_on_destroy = true

  boot_order = ["virtio0", "net0"]

  clone {
    vm_id = local.template_vmid
    full  = true
  }

  agent {
    enabled = true
    type    = "virtio"
    timeout = "30s"
  }

  initialization {
    datastore_id = local.datastore_id
    interface    = "ide2"
    upgrade      = false
  }

  operating_system { type = "l26" }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  vga {
    memory = 16
  }

  disk {
    datastore_id = local.datastore_id
    interface    = "virtio0"
    size         = each.value.disk_size_gb
    file_format  = "raw"
    discard      = "on"
  }

  dynamic "network_device" {
    for_each = { for idx, nic in each.value.nics : idx => nic }
    content {
      bridge      = network_device.value.bridge
      model       = "virtio"
      mac_address = network_device.value.mac
    }
  }

  lifecycle {
    ignore_changes = [clone, disk]
  }
}
