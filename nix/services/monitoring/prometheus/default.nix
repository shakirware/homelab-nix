{ config, lib, pkgs, ... }:

let
  ips = config.homelab.ips;
  baseDomain = config.homelab.baseDomain;

  port = 9090;
  dataDir = "/srv/appdata/prometheus";

  nodePort = 9100;
  pveExporterPort = 9221;

  publicHost = "prometheus.${baseDomain}";
  publicUrl = "https://${publicHost}";

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
              - "gw.${baseDomain}:${toString nodePort}"
              - "media.${baseDomain}:${toString nodePort}"
              - "storage.${baseDomain}:${toString nodePort}"
              - "apps.${baseDomain}:${toString nodePort}"
              - "sensitive.${baseDomain}:${toString nodePort}"
              - "${ips.monitoring}:${toString nodePort}"

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
          - target_label: instance
            replacement: "proxmox"
          - target_label: __address__
            replacement: 127.0.0.1:${toString pveExporterPort}
  '';

  rulesDir = pkgs.runCommand "prometheus-rules" { } ''
    mkdir -p $out
    cat > $out/basics.yml <<'EOF'
    groups:
      - name: basics
        rules:
          - alert: Watchdog
            expr: vector(1)
            labels:
              severity: none
            annotations:
              summary: "Watchdog"
              description: "Alerting pipeline is working."

          - alert: InstanceDown
            expr: up == 0
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "Instance down"
              description: "{{ $labels.job }} target {{ $labels.instance }} is not reachable."

          - alert: HostRebooted
            expr: changes(node_boot_time_seconds[5m]) > 0
            labels:
              severity: info
            annotations:
              summary: "Host rebooted"
              description: "{{ $labels.instance }} reboot detected."

          - alert: HostClockNotSynced
            expr: node_timex_sync_status == 0
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Clock not synced"
              description: "{{ $labels.instance }} reports NTP not synchronized for 10m."

          - alert: HostClockSkew
            expr: abs(node_timex_offset_seconds) > 0.5
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Clock skew"
              description: "{{ $labels.instance }} time offset is {{ $value }}s (>0.5s)."

          - alert: HostHighCpuUsage
            expr: (1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))) > 0.90
            for: 15m
            labels:
              severity: warning
            annotations:
              summary: "High CPU usage"
              description: "{{ $labels.instance }} CPU busy >90% for 15m."

          - alert: HostHighLoad
            expr: (node_load5 / count by(instance) (node_cpu_seconds_total{mode="idle"})) > 2
            for: 15m
            labels:
              severity: warning
            annotations:
              summary: "High load"
              description: "{{ $labels.instance }} load5 per core > 2 for 15m."

          - alert: HostMemoryLowWarning
            expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.10
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Low memory"
              description: "{{ $labels.instance }} MemAvailable <10% for 10m."

          - alert: HostMemoryLowCritical
            expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.05
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Very low memory"
              description: "{{ $labels.instance }} MemAvailable <5% for 5m."

          - alert: HostSwapUsageHigh
            expr: ((node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes) / (node_memory_SwapTotal_bytes + 1)) > 0.80
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "High swap usage"
              description: "{{ $labels.instance }} swap usage >80% for 10m."

          - alert: HostOOMKills
            expr: increase(node_vmstat_oom_kill[10m]) > 0
            labels:
              severity: critical
            annotations:
              summary: "OOM kills"
              description: "{{ $labels.instance }} has OOM kills in the last 10m."

          - alert: HostFilesystemReadOnly
            expr: node_filesystem_readonly{fstype!~"tmpfs|overlay"} == 1
            for: 1m
            labels:
              severity: critical
            annotations:
              summary: "Filesystem read-only"
              description: "{{ $labels.instance }} {{ $labels.mountpoint }} is read-only."

          - alert: HostDiskNearlyFull
            expr: (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) < 0.10
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Disk nearly full"
              description: "{{ $labels.instance }} {{ $labels.mountpoint }} < 10% free."

          - alert: HostDiskFullCritical
            expr: (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) < 0.05
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Disk critically full"
              description: "{{ $labels.instance }} {{ $labels.mountpoint }} < 5% free."

          - alert: HostInodesNearlyFull
            expr: (node_filesystem_files_free{fstype!~"tmpfs|overlay"} / node_filesystem_files{fstype!~"tmpfs|overlay"}) < 0.10
            for: 15m
            labels:
              severity: warning
            annotations:
              summary: "Inodes nearly full"
              description: "{{ $labels.instance }} {{ $labels.mountpoint }} < 10% inodes free."

          - alert: HostNetworkErrors
            expr: sum by(instance, device) (increase(node_network_receive_errs_total{device!="lo"}[5m]) + increase(node_network_transmit_errs_total{device!="lo"}[5m])) > 0
            for: 5m
            labels:
              severity: warning
            annotations:
              summary: "Network errors"
              description: "{{ $labels.instance }} {{ $labels.device }} has RX/TX errors in the last 5m."
    EOF

    cat > $out/systemd.yml <<'EOF'
    groups:
      - name: systemd
        rules:
          - alert: SystemdUnitFailedCritical
            expr: node_systemd_unit_state{state="failed",name=~"(sshd|systemd-networkd|systemd-resolved|tailscaled|unbound|adguardhome|caddy|nfs-server|promtail)\\.service"} == 1
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "Critical systemd unit failed"
              description: "{{ $labels.instance }} unit {{ $labels.name }} is failed."

          - alert: PodmanContainerUnitFailed
            expr: node_systemd_unit_state{state="failed",name=~"podman-(gluetun|qbittorrent|prowlarr|sonarr|radarr|jellyfin|jellyseerr|jellystat|iptv-proxy|profilarr|homepage|couchdb|actual|server_self_hosted|standardnotes_web|db_self_hosted|cache_self_hosted|localstack_self_hosted|prometheus|grafana|loki|alertmanager|proxmox_exporter)\\.service"} == 1
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "Container service failed"
              description: "{{ $labels.instance }} unit {{ $labels.name }} is failed."

          - alert: MediaMountDown
            expr: node_systemd_unit_state{name="srv-media.mount",state="active"} == 0
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "/srv/media not mounted"
              description: "{{ $labels.instance }} srv-media.mount is not active."
    EOF

    cat > $out/proxmox.yml <<'EOF'
    groups:
      - name: proxmox
        rules:
          - alert: ProxmoxNodeOffline
            expr: pve_up{id=~"^node/"} == 0
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "Proxmox node offline"
              description: "Proxmox node {{ $labels.id }} is offline."

          - alert: ProxmoxGuestDownOnBoot
            expr: ((pve_onboot_status{id=~"^(qemu|lxc)/"} == 1) and on(id) (pve_up{id=~"^(qemu|lxc)/"} == 0)) * on(id) group_left(name,node) pve_guest_info
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Proxmox guest down"
              description: "Guest {{ $labels.name }} ({{ $labels.id }}) on {{ $labels.node }} is down but onboot=1."

          - alert: ProxmoxStorageNearlyFull
            expr: (pve_disk_usage_bytes{id=~"^storage/"} / pve_disk_size_bytes{id=~"^storage/"}) > 0.90
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Proxmox storage nearly full"
              description: "{{ $labels.id }} >90% used for 10m."

          - alert: ProxmoxStorageCriticallyFull
            expr: (pve_disk_usage_bytes{id=~"^storage/"} / pve_disk_size_bytes{id=~"^storage/"}) > 0.95
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Proxmox storage critically full"
              description: "{{ $labels.id }} >95% used for 5m."

          - alert: ProxmoxGuestsNotBackedUp
            expr: pve_not_backed_up_total{id=~"^cluster/"} > 0
            for: 1h
            labels:
              severity: warning
            annotations:
              summary: "Guests missing backup coverage"
              description: "{{ $value }} guests are not covered by any backup job."

          - alert: ProxmoxGuestNotBackedUp
            expr: (pve_not_backed_up_info == 1) * on(id) group_left(name,node) pve_guest_info
            for: 1h
            labels:
              severity: warning
            annotations:
              summary: "Guest not covered by backups"
              description: "Guest {{ $labels.name }} ({{ $labels.id }}) is not covered by any backup job."

          - alert: ProxmoxReplicationFailed
            expr: pve_replication_failed_syncs > 0
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Proxmox replication failures"
              description: "{{ $labels.id }} has failed replication syncs ({{ $value }})."
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
      "--web.external-url=${publicUrl}"
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
