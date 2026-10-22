{ config, lib, pkgs, ... }:

# Receives the MikroTik router's remote syslog (firewall decisions, logins,
# system events) and ships it to the local Loki. Runs inside the host's Alloy
# instance as an extra config file, so only vm-monitoring listens.

let
  ips = config.homelab.ips;
  port = 1514;
  lokiPushUrl = "http://127.0.0.1:3100/loki/api/v1/push";
in {
  environment.etc."alloy/router-syslog.alloy".text = ''
    loki.write "router_syslog" {
      endpoint {
        url = "${lokiPushUrl}"
      }
    }

    loki.relabel "router_syslog" {
      forward_to = []

      rule {
        source_labels = ["__syslog_message_severity"]
        target_label  = "level"
      }

      rule {
        source_labels = ["__syslog_message_app_name"]
        target_label  = "topic"
      }
    }

    loki.source.syslog "router" {
      listener {
        address       = "0.0.0.0:${toString port}"
        protocol      = "udp"
        syslog_format = "rfc3164"
        labels        = {
          job  = "router-syslog",
          host = "router",
        }
      }
      relabel_rules = loki.relabel.router_syslog.rules
      forward_to    = [loki.write.router_syslog.receiver]
    }
  '';

  systemd.services.alloy.after = [ "podman-loki.service" ];

  networking.firewall.allowedUDPPorts = lib.mkAfter [ port ];

  # Only the router may send; anything else could forge log lines.
  networking.nftables.tables."router-syslog-guard" = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -50; policy accept;
        udp dport ${toString port} jump router_syslog_guard
      }

      chain router_syslog_guard {
        ip saddr ${ips.router_vlan20} accept
        drop
      }
    '';
  };
}
