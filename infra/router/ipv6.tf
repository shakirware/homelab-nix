# No IPv6 routing until it gets a policy of its own; there is no delegated
# prefix today, so a future one cannot bypass the IPv4 zones.
resource "routeros_ipv6_settings" "this" {
  forward = false
  # With forwarding off, RouterOS would otherwise accept RAs and redirects.
  accept_router_advertisements = "no"
  accept_redirects             = "no"
}
