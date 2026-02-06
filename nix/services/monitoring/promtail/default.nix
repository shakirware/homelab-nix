{ config, lib, pkgs, ... }:

let
  ips = config.homelab.ips;
  host = config.networking.hostName;

  lokiPushUrl = "http://${ips.monitoring}:3100/loki/api/v1/push";

  promtailPort = 0;
  positions = "/var/lib/promtail/positions.yaml";

  cfg = pkgs.writeText "promtail.yaml" ''
    server:
      http_listen_port: ${toString promtailPort}
      grpc_listen_port: 0

    positions:
      filename: ${positions}

    clients:
      - url: ${lokiPushUrl}

    scrape_configs:
      - job_name: systemd-journal
        journal:
          max_age: 12h
          labels:
            job: systemd-journal
            host: ${host}
        relabel_configs:
          - source_labels: ['__journal__systemd_unit']
            target_label: 'unit'
  '';
in {
  systemd.tmpfiles.rules =
    lib.mkAfter [ "d /var/lib/promtail 0750 root root - -" ];

  systemd.services.promtail = {
    description = "Promtail (ship logs to Loki)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      ExecStart = "${pkgs.promtail}/bin/promtail -config.file=${cfg}";
      Restart = "on-failure";
      RestartSec = "3s";
    };
  };
}
