# VLAN 30 (CI): tagged on the Proxmox trunk only. Not in LAN, so the router
# offers it no management, neighbour discovery or MAC-WinBox; its forward and
# input policy is the "ci30:" rules in firewall.tf. Every object here is
# commented "ci30:" so rollback/ci30.rsc can remove exactly these.

resource "routeros_interface_bridge_vlan" "ci" {
  bridge   = "bridge"
  vlan_ids = [tostring(local.ci.vlan_id)]
  tagged   = ["bridge", "ether5"]
  untagged = []
  comment  = "ci30: CI on the Proxmox trunk"
}

resource "routeros_interface_vlan" "ci" {
  interface = "bridge"
  name      = local.ci.interface
  vlan_id   = local.ci.vlan_id
  comment   = "ci30: CI"
}

resource "routeros_ip_address" "ci" {
  address   = "${local.ci.gateway}/24"
  interface = routeros_interface_vlan.ci.name
  comment   = "ci30: CI gateway"
}

resource "routeros_interface_list" "ci" {
  name    = "CI"
  comment = "ci30: VLAN 30, internet only"
}

resource "routeros_interface_list_member" "ci" {
  list      = routeros_interface_list.ci.name
  interface = routeros_interface_vlan.ci.name
  comment   = "ci30: CI"
}

# Destinations CI may not reach even through the WAN: private and CGNAT
# ranges include every internal zone and the PPPoE peer (172.16.0.0/12).
resource "routeros_ip_firewall_addr_list" "ci_blocked" {
  for_each = toset(["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "169.254.0.0/16"])

  list    = "CI_BLOCKED"
  address = each.key
  comment = "ci30: not reachable from CI"
}

# IPv6 forwarding is off router-wide (ipv6.tf); these keep CI closed if it is
# ever enabled, and drop CI's link-local traffic to the router.
locals {
  ci_ipv6_rules = {
    input   = { chain = "input", in_interface_list = "CI", comment = "ci30: no IPv6 to the router from CI" }
    from_ci = { chain = "forward", in_interface_list = "CI", comment = "ci30: no IPv6 forwarding from CI" }
    to_ci   = { chain = "forward", out_interface_list = "CI", comment = "ci30: no IPv6 forwarding into CI" }
  }
}

resource "routeros_ipv6_firewall_filter" "ci" {
  for_each = local.ci_ipv6_rules

  chain              = each.value.chain
  action             = "drop"
  in_interface_list  = try(each.value.in_interface_list, null)
  out_interface_list = try(each.value.out_interface_list, null)
  comment            = each.value.comment

  depends_on = [routeros_interface_list_member.ci]
}

# The IPv6 defconf rules are set by hand. Anchor on input "drop invalid", the
# first rule after established/related (a comment with commas finds nothing).
data "routeros_ipv6_firewall" "first" {
  rules {
    filter = {
      chain   = "input"
      comment = "defconf: drop invalid"
    }
  }
}

# Puts the CI rules just above the anchor, ahead of every defconf accept.
resource "routeros_move_items" "ipv6_filter" {
  resource_path = "/ipv6/firewall/filter"
  sequence = concat(
    [for k in ["input", "from_ci", "to_ci"] : routeros_ipv6_firewall_filter.ci[k].id],
    [data.routeros_ipv6_firewall.first.rules[0].id],
  )
}
