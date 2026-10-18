{ config, lib, pkgs, ... }:

# Receives the MikroTik router's remote syslog (firewall decisions, logins,
# system events) and ships it to the local Loki. A separate Promtail instance
# from the per-host journal shipper, so only vm-monitoring listens.

let
  ips = config.homelab.ips;
  port = 1514;
  lokiPushUrl = "http://127.0.0.1:3100/loki/api/v1/push";

  cfg = pkgs.writeText "router-syslog.yaml" ''
    server:
      http_listen_port: 0
      grpc_listen_port: 0

    positions:
      filename: /var/lib/router-syslog/positions.yaml

    clients:
      - url: ${lokiPushUrl}

    scrape_configs:
      - job_name: router-syslog
        syslog:
          listen_address: 0.0.0.0:${toString port}
          listen_protocol: udp
          syslog_format: rfc3164
          labels:
            job: router-syslog
            host: router
        relabel_configs:
          - source_labels: ['__syslog_message_severity']
            target_label: 'level'
          - source_labels: ['__syslog_message_app_name']
            target_label: 'topic'
  '';
in {
  systemd.services.router-syslog = {
    description = "Receive router syslog and ship it to Loki";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" "podman-loki.service" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.promtail}/bin/promtail -config.file=${cfg}";
      DynamicUser = true;
      StateDirectory = "router-syslog";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };

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
