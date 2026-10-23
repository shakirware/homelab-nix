# VLAN 31 (release): vm-release, the runner that builds and deploys
# production. Same shape as VLAN 30 in ci.tf, but a separate VLAN and
# interface list, so the "rel31:" rules in firewall.tf keep CI and release
# apart. Every object here is commented "rel31:" so rollback/rel31.rsc can
# remove exactly these.

resource "routeros_interface_bridge_vlan" "release" {
  bridge   = "bridge"
  vlan_ids = [tostring(local.release.vlan_id)]
  tagged   = ["bridge", "ether5"]
  untagged = []
  comment  = "rel31: release on the Proxmox trunk"
}

resource "routeros_interface_vlan" "release" {
  interface = "bridge"
  name      = local.release.interface
  vlan_id   = local.release.vlan_id
  comment   = "rel31: release"
}

resource "routeros_ip_address" "release" {
  address   = "${local.release.gateway}/24"
  interface = routeros_interface_vlan.release.name
  comment   = "rel31: release gateway"
}

resource "routeros_interface_list" "release" {
  name    = "RELEASE"
  comment = "rel31: VLAN 31, internet only"
}

resource "routeros_interface_list_member" "release" {
  list      = routeros_interface_list.release.name
  interface = routeros_interface_vlan.release.name
  comment   = "rel31: release"
}

# Its own copy of CI_BLOCKED, so either rollback leaves the other intact.
resource "routeros_ip_firewall_addr_list" "release_blocked" {
  for_each = toset(["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "169.254.0.0/16"])

  list    = "RELEASE_BLOCKED"
  address = each.key
  comment = "rel31: not reachable from release"
}

# Ordered by routeros_move_items.ipv6_filter in ci.tf.
locals {
  release_ipv6_rules = {
    input        = { chain = "input", in_interface_list = "RELEASE", comment = "rel31: no IPv6 to the router from release" }
    from_release = { chain = "forward", in_interface_list = "RELEASE", comment = "rel31: no IPv6 forwarding from release" }
    to_release   = { chain = "forward", out_interface_list = "RELEASE", comment = "rel31: no IPv6 forwarding into release" }
  }
}

resource "routeros_ipv6_firewall_filter" "release" {
  for_each = local.release_ipv6_rules

  chain              = each.value.chain
  action             = "drop"
  in_interface_list  = try(each.value.in_interface_list, null)
  out_interface_list = try(each.value.out_interface_list, null)
  comment            = each.value.comment

  depends_on = [routeros_interface_list_member.release]
}
