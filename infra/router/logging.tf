# Router logs (firewall decisions, logins, system events) go to Loki through
# the receiver in nix/services/monitoring/router-syslog.

resource "routeros_system_logging_action" "remote" {
  name               = "remote"
  target             = "remote"
  remote             = local.ips.monitoring
  remote_port        = 1514
  remote_protocol    = "udp"
  src_address        = local.ips.router_vlan20
  remote_log_format  = "syslog"
  syslog_time_format = "bsd-syslog"
  syslog_facility    = "local0"
}

# One rule per topic: a rule matches only messages carrying all its topics.
resource "routeros_system_logging" "remote" {
  for_each = toset(["info", "warning", "error", "critical"])

  topics = [each.key]
  action = routeros_system_logging_action.remote.name
}
