# Bridge VLANs. VLAN 20 (SERVERS, tagged to the Proxmox trunk on ether5) is
# still set by hand; VLAN 40 never goes to the trunk.

resource "routeros_interface_bridge_vlan" "trusted" {
  bridge   = "bridge"
  vlan_ids = ["1"]
  tagged   = []
  untagged = ["bridge", "ether2", "ether3", "ether5"]
}

resource "routeros_interface_bridge_vlan" "iot" {
  bridge   = "bridge"
  vlan_ids = [tostring(local.iot.vlan_id)]
  tagged   = ["bridge"]
  untagged = local.iot.ports
  comment  = "${local.iot_tag}: IoT and TVs"
}

# Adopted defconf ports: only PVID and horizon are managed.
resource "routeros_interface_bridge_port" "iot" {
  for_each = toset(local.iot.ports)

  bridge      = "bridge"
  interface   = each.key
  pvid        = local.iot.vlan_id
  frame_types = "admit-only-untagged-and-priority-tagged"
  # A shared horizon stops the bridge forwarding between the two IoT radios;
  # the wired hub has none so it still reaches its Wi-Fi cameras.
  horizon = startswith(each.key, "wifi") ? "40" : "none"
  comment = "defconf"
}

resource "routeros_interface_vlan" "iot" {
  interface = "bridge"
  name      = local.iot.interface
  vlan_id   = local.iot.vlan_id
  comment   = "${local.iot_tag}: IoT and TVs"
}

resource "routeros_ip_address" "iot" {
  address   = "${local.iot.gateway}/24"
  interface = routeros_interface_vlan.iot.name
  comment   = "${local.iot_tag}: IoT gateway"
}
