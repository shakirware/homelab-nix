# Router services. IP services (SSH, WinBox, web, API) are set by
# services.rsc instead: routeros_ip_service in provider 1.99.1 cannot import
# (it re-reads "?name=<.id>") and resolves services by name, which is
# ambiguous with a dynamic row per open connection. User accounts are
# operator-owned too (users.rsc): a netwatch rollback cannot change them.

resource "routeros_system_ntp_client" "this" {
  enabled = true
  servers = ["0.uk.pool.ntp.org", "1.uk.pool.ntp.org", "2.uk.pool.ntp.org"]
}

resource "routeros_ip_ssh_server" "this" {
  strong_crypto = true
}

resource "routeros_tool_bandwidth_server" "this" {
  enabled = false
}

resource "routeros_ip_smb" "this" {
  enabled = "no"
}

resource "routeros_disk_settings" "this" {
  auto_media_sharing = false
  auto_smb_sharing   = false
}

# MAC-WinBox is the emergency path if the admin workstation is lost: it works
# at layer 2 from TRUSTED, regardless of addresses and firewall rules. Not
# from SERVERS or IOT. MAC-Telnet is plaintext, so it is off.
resource "routeros_tool_mac_server_winbox" "this" {
  allowed_interface_list = routeros_interface_list.trusted.name
}

resource "routeros_tool_mac_server" "this" {
  allowed_interface_list = "none"
}
