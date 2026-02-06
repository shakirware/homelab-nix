{ config, lib, pkgs, ... }:

let
  appDir = "/srv/appdata/loki";
  port = 3100;

  lokiYaml = pkgs.writeText "loki.yaml" ''
    auth_enabled: false

    server:
      http_listen_port: ${toString port}

    common:
      path_prefix: /loki
      storage:
        filesystem:
          chunks_directory: /loki/chunks
          rules_directory: /loki/rules
      replication_factor: 1
      ring:
        kvstore:
          store: inmemory

    schema_config:
      configs:
        - from: 2024-01-01
          store: tsdb
          object_store: filesystem
          schema: v13
          index:
            prefix: index_
            period: 24h

    limits_config:
      retention_period: 30d
      ingestion_rate_mb: 16
      ingestion_burst_size_mb: 32

    ruler:
      alertmanager_url: http://127.0.0.1:9093
  '';
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${appDir} 0750 10001 10001 - -"
    "d ${appDir}/data 0750 10001 10001 - -"
  ];

  virtualisation.oci-containers.containers.loki = {
    image = "grafana/loki:2.9.8";
    autoStart = true;

    cmd = [ "-config.file=/etc/loki/loki.yaml" ];

    volumes = [ "${appDir}/data:/loki" "${lokiYaml}:/etc/loki/loki.yaml:ro" ];

    ports = [ ];

    extraOptions = [ "--network=host" "--name=loki" ];
  };

  systemd.services.podman-loki = {
    after = [ "podman.service" ];
    requires = [ "podman.service" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

}
