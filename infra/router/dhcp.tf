# VLAN 40 DHCP. The VLAN 1 server (defconf) and its pinned leases are set by
# hand.

resource "routeros_ip_pool" "iot" {
  name    = "iot-dhcp"
  ranges  = [local.iot.pool]
  comment = "${local.iot_tag}: dynamic IoT addresses (.2-.99 are reservations)"
}

resource "routeros_ip_dhcp_server" "iot" {
  name         = "iot"
  interface    = routeros_interface_vlan.iot.name
  address_pool = routeros_ip_pool.iot.name
  lease_time   = "1d"
  # Refuse a stale address at once instead of letting the client wait it out.
  authoritative = "yes"
  comment       = "${local.iot_tag}: IoT and TVs"
}

resource "routeros_ip_dhcp_server_network" "iot" {
  address    = local.iot.cidr
  gateway    = local.iot.gateway
  dns_server = [local.ips.gw]
  comment    = "${local.iot_tag}: IoT and TVs"
}

resource "routeros_ip_dhcp_server_lease" "iot" {
  for_each = var.iot_reservations

  server      = routeros_ip_dhcp_server.iot.name
  address     = each.value.ip
  mac_address = each.value.mac
  comment     = "${local.iot_tag}: ${each.key} (${each.value.role})${each.value.comment == "" ? "" : ": ${each.value.comment}"}"
}
