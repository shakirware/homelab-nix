# Zone-based IPv4 firewall. Zones are interface lists; the defconf "LAN" list
# stays the union of TRUSTED and SERVERS for MAC-WinBox, neighbour discovery
# and the IPv6 defaults. IOT is deliberately not in LAN.

resource "routeros_interface_list" "trusted" {
  name    = "TRUSTED"
  comment = "VLAN 1: workstation, phones, home devices"
}

resource "routeros_interface_list" "servers" {
  name    = "SERVERS"
  comment = "VLAN 20: Proxmox and the NixOS VMs"
}

resource "routeros_interface_list" "iot" {
  name    = "IOT"
  comment = "VLAN 40: IoT devices and TVs"
}

resource "routeros_interface_list_member" "trusted_bridge" {
  list      = routeros_interface_list.trusted.name
  interface = "bridge"
}

resource "routeros_interface_list_member" "servers_vlan20" {
  list      = routeros_interface_list.servers.name
  interface = "vlan20"
}

resource "routeros_interface_list_member" "iot" {
  list      = routeros_interface_list.iot.name
  interface = routeros_interface_vlan.iot.name
}

resource "routeros_ip_firewall_addr_list" "admin" {
  for_each = local.admin_hosts

  list    = "ADMIN"
  address = each.key
  comment = each.value
}

resource "routeros_ip_firewall_addr_list" "tv_devices" {
  for_each = { for k, r in var.iot_reservations : k => r if contains(["apple_tv", "tv"], r.role) }

  list    = "TV_DEVICES"
  address = each.value.ip
  comment = "${local.iot_tag}: ${each.key}"
}

# --- defconf rules, adopted unchanged -------------------------------------

locals {
  defconf = {
    in_established   = { chain = "input", action = "accept", connection_state = "established,related,untracked", comment = "defconf: accept established,related,untracked" }
    in_invalid       = { chain = "input", action = "drop", connection_state = "invalid", comment = "defconf: drop invalid" }
    in_icmp          = { chain = "input", action = "accept", protocol = "icmp", comment = "defconf: accept ICMP" }
    in_loopback      = { chain = "input", action = "accept", dst_address = "127.0.0.1", comment = "defconf: accept to local loopback (for CAPsMAN)" }
    in_not_lan       = { chain = "input", action = "drop", in_interface_list = "!LAN", comment = "defconf: drop all not coming from LAN" }
    fw_ipsec_in      = { chain = "forward", action = "accept", ipsec_policy = "in,ipsec", comment = "defconf: accept in ipsec policy" }
    fw_ipsec_out     = { chain = "forward", action = "accept", ipsec_policy = "out,ipsec", comment = "defconf: accept out ipsec policy" }
    fw_fasttrack     = { chain = "forward", action = "fasttrack-connection", connection_state = "established,related", hw_offload = true, comment = "defconf: fasttrack" }
    fw_established   = { chain = "forward", action = "accept", connection_state = "established,related,untracked", comment = "defconf: accept established,related, untracked" }
    fw_invalid       = { chain = "forward", action = "drop", connection_state = "invalid", comment = "defconf: drop invalid" }
    fw_wan_no_dstnat = { chain = "forward", action = "drop", connection_state = "new", connection_nat_state = "!dstnat", in_interface_list = "WAN", comment = "defconf: drop all from WAN not DSTNATed" }
  }
}

resource "routeros_ip_firewall_filter" "defconf" {
  for_each = local.defconf

  chain                = each.value.chain
  action               = each.value.action
  comment              = each.value.comment
  connection_state     = try(each.value.connection_state, null)
  connection_nat_state = try(each.value.connection_nat_state, null)
  in_interface_list    = try(each.value.in_interface_list, null)
  protocol             = try(each.value.protocol, null)
  dst_address          = try(each.value.dst_address, null)
  ipsec_policy         = try(each.value.ipsec_policy, null)
  hw_offload           = try(each.value.hw_offload, null)
}

# --- zone policy, in chain order --------------------------------------------
# Rules match new connections unless they set connection_state.

locals {
  input_rules = concat([
    # Before the ADMIN accept, so a CI host spoofing the workstation's
    # address cannot open router management. Ping the gateway still works.
    { key = "in_ci_drop", action = "drop", in_interface_list = "CI", connection_state = null, log = true, log_prefix = "FW-CI-IN", comment = "ci30: no router access from CI" },
    { key = "in_rel_drop", action = "drop", in_interface_list = "RELEASE", connection_state = null, log = true, log_prefix = "FW-REL-IN", comment = "rel31: no router access from RELEASE" },
    { key = "in_dhcp_trusted", action = "accept", protocol = "udp", dst_port = "67", in_interface_list = "TRUSTED", comment = "zones: DHCP for TRUSTED" },
    { key = "in_admin", action = "accept", protocol = "tcp", dst_port = "22,80,443,8291", src_address_list = "ADMIN", comment = "zones: router management from ADMIN hosts" },
    { key = "in_gw_web", action = "accept", protocol = "tcp", dst_port = "80", src_address = local.ips.gw, comment = "zones: router web UI for vm-gw (router.shakr.dev)" },
    { key = "in_dhcp_iot", action = "accept", protocol = "udp", dst_port = "67", in_interface_list = "IOT", comment = "zones: DHCP for IOT" },
    { key = "in_mdns_trusted", action = "accept", protocol = "udp", dst_port = "5353", dst_address = "224.0.0.251", in_interface_list = "TRUSTED", connection_state = null, comment = "zones: mDNS to the repeater from TRUSTED" },
    { key = "in_mdns_iot", action = "accept", protocol = "udp", dst_port = "5353", dst_address = "224.0.0.251", in_interface_list = "IOT", connection_state = null, comment = "zones: mDNS to the repeater from IOT" },
    # The rest of IOT's input is dropped by defconf "not from LAN" below.
    { key = "in_iot_log", action = "log", in_interface_list = "IOT", dst_address_type = "local", log_prefix = "FW-IOT-IN", comment = "zones: log unmatched input from IOT" },
    { key = "in_log", action = "log", in_interface_list = "LAN", dst_address_type = "local", log_prefix = local.firewall_enforce ? "FW-DROP-IN" : "FW-OBS-IN", comment = "zones: log unmatched input from internal zones" },
    ], local.firewall_enforce ? [
    { key = "in_drop", action = "drop", in_interface_list = "LAN", comment = "zones: drop unmatched input from internal zones" },
  ] : [])

  forward_rules = concat([
    # CI first: internet only, and only the workstation (SSH) and
    # vm-monitoring (node exporter) may open connections into it. The
    # in_interface_list matches stop other zones spoofing those sources.
    { key = "fw_ci_spoof", action = "drop", in_interface_list = "CI", src_address = "!${local.ci.cidr}", log = true, log_prefix = "FW-CI-SPOOF", comment = "ci30: drop spoofed sources from CI" },
    { key = "fw_ci_blocked", action = "drop", in_interface_list = "CI", dst_address_list = "CI_BLOCKED", log = true, log_prefix = "FW-CI-DROP", comment = "ci30: CI -> private ranges" },
    { key = "fw_ci_internal", action = "drop", in_interface_list = "CI", out_interface_list = "!WAN", log = true, log_prefix = "FW-CI-DROP", comment = "ci30: CI -> internal zones" },
    { key = "fw_ci_wan", action = "accept", in_interface_list = "CI", out_interface_list = "WAN", comment = "ci30: CI -> internet" },
    { key = "fw_ci_ssh", action = "accept", in_interface_list = "TRUSTED", src_address_list = "ADMIN", dst_address = local.ci.host, protocol = "tcp", dst_port = "22", comment = "ci30: ADMIN -> vm-ci SSH" },
    { key = "fw_ci_metrics", action = "accept", in_interface_list = "SERVERS", src_address = local.ips.monitoring, dst_address = local.ci.host, protocol = "tcp", dst_port = "9100", comment = "ci30: vm-monitoring -> vm-ci node exporter" },
    { key = "fw_ci_in_drop", action = "drop", out_interface_list = "CI", log = true, log_prefix = "FW-CI-IN", comment = "ci30: nothing else into CI" },
    # RELEASE: the same policy for vm-release, on its own VLAN and list.
    { key = "fw_rel_spoof", action = "drop", in_interface_list = "RELEASE", src_address = "!${local.release.cidr}", log = true, log_prefix = "FW-REL-SPOOF", comment = "rel31: drop spoofed sources from RELEASE" },
    { key = "fw_rel_blocked", action = "drop", in_interface_list = "RELEASE", dst_address_list = "RELEASE_BLOCKED", log = true, log_prefix = "FW-REL-DROP", comment = "rel31: RELEASE -> private ranges" },
    { key = "fw_rel_internal", action = "drop", in_interface_list = "RELEASE", out_interface_list = "!WAN", log = true, log_prefix = "FW-REL-DROP", comment = "rel31: RELEASE -> internal zones" },
    { key = "fw_rel_wan", action = "accept", in_interface_list = "RELEASE", out_interface_list = "WAN", comment = "rel31: RELEASE -> internet" },
    { key = "fw_rel_ssh", action = "accept", in_interface_list = "TRUSTED", src_address_list = "ADMIN", dst_address = local.release.host, protocol = "tcp", dst_port = "22", comment = "rel31: ADMIN -> vm-release SSH" },
    { key = "fw_rel_metrics", action = "accept", in_interface_list = "SERVERS", src_address = local.ips.monitoring, dst_address = local.release.host, protocol = "tcp", dst_port = "9100", comment = "rel31: vm-monitoring -> vm-release node exporter" },
    { key = "fw_rel_in_drop", action = "drop", out_interface_list = "RELEASE", log = true, log_prefix = "FW-REL-IN", comment = "rel31: nothing else into RELEASE" },
    { key = "fw_trusted_wan", action = "accept", in_interface_list = "TRUSTED", out_interface_list = "WAN", comment = "zones: TRUSTED -> internet" },
    { key = "fw_servers_wan", action = "accept", in_interface_list = "SERVERS", out_interface_list = "WAN", comment = "zones: SERVERS -> internet" },
    { key = "fw_admin_servers", action = "accept", src_address_list = "ADMIN", out_interface_list = "SERVERS", comment = "zones: ADMIN hosts -> SERVERS" },
    { key = "fw_trusted_dns_udp", action = "accept", in_interface_list = "TRUSTED", dst_address = local.ips.gw, protocol = "udp", dst_port = "53", comment = "zones: TRUSTED -> AdGuard DNS" },
    { key = "fw_trusted_gw_tcp", action = "accept", in_interface_list = "TRUSTED", dst_address = local.ips.gw, protocol = "tcp", dst_port = "53,80,443", comment = "zones: TRUSTED -> AdGuard DNS and Caddy" },
    { key = "fw_trusted_ping", action = "accept", in_interface_list = "TRUSTED", out_interface_list = "SERVERS", protocol = "icmp", comment = "zones: TRUSTED -> ping servers" },
    # Trusted devices also need HTTP/3 to Caddy, vm-media's own address
    # (Jellyfin apps, and TuliProx, whose playlists carry it) and Tailscale's
    # direct path to vm-gw.
    { key = "fw_trusted_gw_quic", action = "accept", in_interface_list = "TRUSTED", dst_address = local.ips.gw, protocol = "udp", dst_port = "443", comment = "zones: TRUSTED -> Caddy HTTP/3" },
    { key = "fw_trusted_jellyfin", action = "accept", in_interface_list = "TRUSTED", dst_address = local.ips.media, protocol = "tcp", dst_port = "8096,8901", comment = "zones: TRUSTED -> Jellyfin and TuliProx direct" },
    { key = "fw_trusted_tailscale", action = "accept", in_interface_list = "TRUSTED", dst_address = local.ips.gw, protocol = "udp", dst_port = "41641", comment = "zones: TRUSTED -> Tailscale direct to vm-gw" },

    # IOT is strict regardless of firewall_enforce: everything not accepted
    # here is dropped by fw_iot_drop.
    { key = "fw_iot_scan_mark", action = "add-src-to-address-list", in_interface_list = "IOT", protocol = "tcp", psd = "21,3s,3,1", address_list = "iot-scanners", address_list_timeout = "1d", comment = "zones: quarantine IOT port scanners" },
    { key = "fw_iot_scan_drop", action = "drop", connection_state = null, src_address_list = "iot-scanners", comment = "zones: drop quarantined IOT scanners" },
    { key = "fw_iot_dot", action = "drop", in_interface_list = "IOT", protocol = "tcp", dst_port = "853", comment = "zones: no DNS-over-TLS from IOT (bypasses AdGuard)" },
    { key = "fw_iot_wan", action = "accept", in_interface_list = "IOT", out_interface_list = "WAN", comment = "zones: IOT -> internet" },
    { key = "fw_iot_dns_udp", action = "accept", in_interface_list = "IOT", dst_address = local.ips.gw, protocol = "udp", dst_port = "53", comment = "zones: IOT -> AdGuard DNS" },
    { key = "fw_iot_gw_tcp", action = "accept", in_interface_list = "IOT", dst_address = local.ips.gw, protocol = "tcp", dst_port = "53,80,443", comment = "zones: IOT -> AdGuard DNS and Caddy (Jellyfin, Infuse, HA)" },
    { key = "fw_iot_gw_ping", action = "accept", in_interface_list = "IOT", dst_address = local.ips.gw, protocol = "icmp", comment = "zones: IOT -> ping AdGuard" },
    # The TV apps and TuliProx playlists use vm-media's own address.
    { key = "fw_iot_media", action = "accept", src_address_list = "TV_DEVICES", in_interface_list = "IOT", dst_address = local.ips.media, protocol = "tcp", dst_port = "8096,8901", comment = "zones: IOT TVs -> Jellyfin and TuliProx direct" },
    { key = "fw_trusted_iot", action = "accept", in_interface_list = "TRUSTED", out_interface_list = "IOT", comment = "zones: TRUSTED -> IOT (apps, casting, AirPlay senders)" },
    { key = "fw_ha_iot", action = "accept", src_address = local.ips.apps, out_interface_list = "IOT", comment = "zones: Home Assistant -> IOT" },
    # AirPlay receivers open PTP (319/320), timing (7000-7011) and dynamic
    # UDP ports back to the sender; never to the ADMIN hosts.
    { key = "fw_airplay_udp", action = "accept", src_address_list = "TV_DEVICES", out_interface_list = "TRUSTED", dst_address_list = "!ADMIN", protocol = "udp", dst_port = "319,320,7000-7011,49152-65535", log = true, log_prefix = "FW-AIRPLAY", comment = "zones: AirPlay receiver -> sender return (UDP)" },
    { key = "fw_iot_log", action = "log", in_interface_list = "IOT", log_prefix = "FW-IOT-DROP", comment = "zones: log IOT -> internal" },
    { key = "fw_iot_drop", action = "drop", in_interface_list = "IOT", comment = "zones: drop IOT -> internal" },

    # Not rate-limited, so every unmatched flow is logged.
    { key = "fw_log", action = "log", log_prefix = local.firewall_enforce ? "FW-DROP-FWD" : "FW-OBS-FWD", comment = "zones: log unmatched forward" },
    ], local.firewall_enforce ? [
    { key = "fw_drop", action = "drop", comment = "zones: drop unmatched forward" },
  ] : [])

  zone_rules = merge(
    { for r in local.input_rules : r.key => merge(r, { chain = "input" }) },
    { for r in local.forward_rules : r.key => merge(r, { chain = "forward" }) },
  )
}

resource "routeros_ip_firewall_filter" "zones" {
  for_each = local.zone_rules

  chain                = each.value.chain
  action               = each.value.action
  comment              = each.value.comment
  connection_state     = try(each.value.connection_state, "new")
  protocol             = try(each.value.protocol, null)
  dst_port             = try(each.value.dst_port, null)
  src_address          = try(each.value.src_address, null)
  dst_address          = try(each.value.dst_address, null)
  src_address_list     = try(each.value.src_address_list, null)
  dst_address_list     = try(each.value.dst_address_list, null)
  in_interface_list    = try(each.value.in_interface_list, null)
  out_interface_list   = try(each.value.out_interface_list, null)
  dst_address_type     = try(each.value.dst_address_type, null)
  log_prefix           = try(each.value.log_prefix, null)
  log                  = try(each.value.log, null)
  psd                  = try(each.value.psd, null)
  address_list         = try(each.value.address_list, null)
  address_list_timeout = try(each.value.address_list_timeout, null)

  depends_on = [
    routeros_interface_list_member.trusted_bridge,
    routeros_interface_list_member.servers_vlan20,
    routeros_interface_list_member.iot,
    routeros_ip_firewall_addr_list.admin,
    routeros_ip_firewall_addr_list.tv_devices,
    routeros_interface_list_member.ci,
    routeros_ip_firewall_addr_list.ci_blocked,
    routeros_interface_list_member.release,
    routeros_ip_firewall_addr_list.release_blocked,
  ]
}

# RouterOS evaluates rules in list order; this pins it.
resource "routeros_move_items" "filter" {
  resource_path = "/ip/firewall/filter"
  sequence = concat(
    [for k in ["in_established", "in_invalid", "in_icmp", "in_loopback"] : routeros_ip_firewall_filter.defconf[k].id],
    [for r in local.input_rules : routeros_ip_firewall_filter.zones[r.key].id],
    [routeros_ip_firewall_filter.defconf["in_not_lan"].id],
    [for k in ["fw_ipsec_in", "fw_ipsec_out", "fw_fasttrack", "fw_established", "fw_invalid", "fw_wan_no_dstnat"] : routeros_ip_firewall_filter.defconf[k].id],
    [for r in local.forward_rules : routeros_ip_firewall_filter.zones[r.key].id],
  )
}
