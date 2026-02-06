{ config, lib, pkgs, ... }:

let
  ips = config.homelab.ips;

  port = 9090;
  dataDir = "/srv/appdata/prometheus";

  nodePort = 9100;
  pveExporterPort = 9221;

  prometheusYaml = pkgs.writeText "prometheus.yml" ''
    global:
      scrape_interval: 15s
      evaluation_interval: 15s

    alerting:
      alertmanagers:
        - static_configs:
            - targets: [ "127.0.0.1:9093" ]

    rule_files:
      - /etc/prometheus/rules/*.yml

    scrape_configs:
      - job_name: "prometheus"
        static_configs:
          - targets: [ "127.0.0.1:${toString port}" ]

      - job_name: "node"
        static_configs:
          - targets:
              - "${ips.gw}:${toString nodePort}"
              - "${ips.media}:${toString nodePort}"
              - "${ips.storage}:${toString nodePort}"
              - "${ips.apps}:${toString nodePort}"
              - "${ips.sensitive}:${toString nodePort}"
              - "${ips.monitoring}:${toString nodePort}"

      # Proxmox VE via prometheus-pve-exporter running locally on vm-monitoring.
      # This MUST hit /pve and pass target=<proxmox-host> via relabeling.
      - job_name: "proxmox"
        metrics_path: /pve
        params:
          module: [default]
          cluster: ['1']
          node: ['1']
        static_configs:
          - targets: [ "${ips.proxmox}" ]
        relabel_configs:
          - source_labels: [__address__]
            target_label: __param_target
          - source_labels: [__param_target]
            target_label: instance
          - target_label: __address__
            replacement: 127.0.0.1:${toString pveExporterPort}
  '';

  rulesDir = pkgs.runCommand "prometheus-rules" { } ''
    mkdir -p $out
    cat > $out/basics.yml <<'EOF'
    groups:
      - name: basics
        rules:
          - alert: InstanceDown
            expr: up == 0
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "Instance down"
              description: "{{ $labels.instance }} is not reachable."

          - alert: HostDiskNearlyFull
            expr: (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) < 0.10
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Disk nearly full"
              description: "{{ $labels.instance }} {{ $labels.mountpoint }} < 10% free."
    EOF
  '';
in {
  systemd.tmpfiles.rules = lib.mkAfter [ "d ${dataDir} 0750 65534 65534 - -" ];

  virtualisation.oci-containers.containers.prometheus = {
    image = "prom/prometheus:v2.52.0";
    autoStart = true;

    cmd = [
      "--config.file=/etc/prometheus/prometheus.yml"
      "--storage.tsdb.path=/prometheus"
      "--storage.tsdb.retention.time=30d"
      "--web.enable-lifecycle"
    ];

    volumes = [
      "${dataDir}:/prometheus"
      "${prometheusYaml}:/etc/prometheus/prometheus.yml:ro"
      "${rulesDir}:/etc/prometheus/rules:ro"
    ];

    ports = [ ];

    extraOptions = [ "--network=host" "--name=prometheus" ];
  };

  systemd.services.podman-prometheus = {
    after = [ "podman.service" ];
    requires = [ "podman.service" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];
}
