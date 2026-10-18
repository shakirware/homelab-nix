# The router is not a resolver: every network uses AdGuard on vm-gw.
resource "routeros_ip_dns" "this" {
  allow_remote_requests = false
  # Discovery for AirPlay, casting and vendor apps across TRUSTED and IOT.
  # It repeats names only; the firewall decides what may connect.
  mdns_repeat_ifaces = ["bridge", local.iot.interface]
}

# IoT DNS to any other resolver is answered by AdGuard, so hard-coded
# resolvers are still filtered.
resource "routeros_ip_firewall_nat" "iot_dns" {
  for_each = toset(["udp", "tcp"])

  chain             = "dstnat"
  action            = "dst-nat"
  in_interface_list = routeros_interface_list.iot.name
  protocol          = each.key
  dst_port          = "53"
  dst_address       = "!${local.ips.gw}"
  to_addresses      = local.ips.gw
  comment           = "zones: IOT DNS -> AdGuard (${each.key})"
}
