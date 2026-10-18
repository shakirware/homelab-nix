# The trusted SSID is a virtual AP on each radio, on VLAN 1. The radios' own
# (inline) SSIDs carry the IoT network and are set by hand, so their
# passphrases never enter the state.

resource "routeros_wifi_security" "trusted" {
  name                  = "trusted"
  authentication_types  = ["wpa2-psk", "wpa3-psk"]
  passphrase            = var.trusted_wifi_passphrase
  management_protection = "allowed" # required by WPA3, optional for WPA2
  ft                    = true      # roaming between the bands
  ft_over_ds            = true

  lifecycle {
    # The tofu account has no "sensitive" right, so the API returns the
    # passphrase masked and every plan would rewrite it. Rotation is manual
    # (docs/network.md).
    ignore_changes = [passphrase]
  }
}

resource "routeros_wifi_datapath" "trusted" {
  name   = "trusted"
  bridge = "bridge" # untagged, PVID 1
}

resource "routeros_wifi_configuration" "trusted" {
  name     = "trusted"
  mode     = "ap"
  ssid     = var.trusted_ssid
  security = { config = routeros_wifi_security.trusted.name }
  datapath = { config = routeros_wifi_datapath.trusted.name }
}

resource "routeros_wifi" "trusted" {
  for_each = { "wifi1-trusted" = "wifi1", "wifi2-trusted" = "wifi2" } # 5 GHz, 2.4 GHz

  name             = each.key
  master_interface = each.value
  configuration    = { config = routeros_wifi_configuration.trusted.name }
  disabled         = false
}

# Client isolation on the IoT radios. Matches the master interfaces only, not
# the trusted virtual APs.
resource "routeros_wifi_access_list" "iot_isolation" {
  for_each = toset(["wifi1", "wifi2"])

  interface        = each.key
  action           = "accept"
  client_isolation = true
  comment          = "${local.iot_tag}: isolate IoT clients on ${each.key}"
}
