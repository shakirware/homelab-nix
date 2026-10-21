locals {
  # Mirrors nix/modules/common/addresses.nix.
  ips = {
    router_vlan20 = "192.168.20.1"
    gw            = "192.168.20.2" # AdGuard, Caddy
    media         = "192.168.20.120"
    apps          = "192.168.20.130" # Home Assistant
    monitoring    = "192.168.20.150"
  }

  # Hosts allowed to manage the router and to reach every server.
  admin_hosts = { "192.168.1.74" = "admin workstation" }

  iot = {
    vlan_id   = 40
    interface = "vlan40-iot"
    gateway   = "192.168.40.1"
    cidr      = "192.168.40.0/24"
    pool      = "192.168.40.100-192.168.40.199"
    ports     = ["wifi1", "wifi2", "ether4"] # the IoT SSIDs and the Reolink hub
  }

  # Internet-only network for a future self-hosted CI runner. Static
  # addressing: no DHCP, DNS or NTP from the router.
  ci = {
    vlan_id   = 30
    interface = "vlan30-ci"
    gateway   = "192.168.30.1"
    cidr      = "192.168.30.0/24"
    host      = "192.168.30.10" # vm-ci
  }

  # false: unmatched traffic from TRUSTED and SERVERS is only logged (FW-OBS-*).
  # true: it is dropped (FW-DROP-*). See docs/network.md before changing.
  firewall_enforce = true

  # Router-side comment prefix on the 26 IoT objects. Kept: changing it edits
  # the IoT access-list entries, which disconnects every IoT Wi-Fi client.
  iot_tag = "phase4"
}
