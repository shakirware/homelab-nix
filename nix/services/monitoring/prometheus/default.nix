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

  blackboxPort = 9115;

  # Unauthenticated health endpoints per vhost; anything not listed is probed
  # at "/". Every Caddy vhost is probed, so new services are covered by default.
  probePaths = {
    grafana = "/api/health";
    prometheus = "/-/healthy";
    alertmanager = "/-/healthy";
    loki = "/ready";
    jellyfin = "/health";
    homeassistant = "/manifest.json";
    actual = "/health";
    notes-api = "/healthcheck";
    notes-files = "/healthcheck";
    yamtrack = "/health/";
    seerr = "/api/v1/status";
    audiobookshelf = "/healthcheck";
    sonarr = "/ping";
    radarr = "/ping";
    prowlarr = "/ping";
    grimmory = "/api/v1/healthcheck";
    shelfmark = "/api/health";
    readmeabook = "/api/health";
    tracearr = "/health";
    cleanuparr = "/health";
    pinchflat = "/healthcheck";
    obsidian-sync = "/_up";
  };

  # CouchDB requires auth on every path; a 401 still proves it is serving.
  authRequiredProbes = [ "obsidian-sync" ];

  probeTargets = map (h:
    let name = lib.removeSuffix ".${baseDomain}" h.host;
    in {
      targets = [ "https://${h.host}${probePaths.${name} or "/"}" ];
      labels = {
        service = name;
        module = if lib.elem name authRequiredProbes then
          "http_auth_required"
        else
          "http_2xx";
      };
    }) config.homelab.webHosts;

  # Flip to true once a backup job exports the metrics described in
  # backups.yml; until then the rules are shipped but not loaded, so nothing
  # claims backups are healthy.
  backupAlertsEnabled = false;

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

      - job_name: "alertmanager"
        static_configs:
          - targets: [ "127.0.0.1:9093" ]

      - job_name: "loki"
        static_configs:
          - targets: [ "127.0.0.1:3100" ]

      - job_name: "node"
        static_configs:
          - targets:
              - "gw.${baseDomain}:${toString nodePort}"
              - "media.${baseDomain}:${toString nodePort}"
              - "storage.${baseDomain}:${toString nodePort}"
              - "apps.${baseDomain}:${toString nodePort}"
              - "sensitive.${baseDomain}:${toString nodePort}"
              - "${ips.monitoring}:${toString nodePort}"

      - job_name: "node-proxmox"
        static_configs:
          - targets: [ "${ips.proxmox}:${toString nodePort}" ]
            labels:
              host: "proxmox"

      - job_name: "proxmox"
        metrics_path: /pve
        params:
          module: [ default ]
          cluster: [ '1' ]
          node: [ '1' ]
        static_configs:
          - targets: [ "${ips.proxmox}" ]
        relabel_configs:
          - source_labels: [ __address__ ]
            target_label: __param_target
          - target_label: instance
            replacement: "proxmox"
          - target_label: __address__
            replacement: 127.0.0.1:${toString pveExporterPort}

      - job_name: "blackbox"
        static_configs:
          - targets: [ "127.0.0.1:${toString blackboxPort}" ]

      - job_name: "blackbox-http"
        metrics_path: /probe
        scrape_interval: 30s
        scrape_timeout: 15s
        static_configs: ${builtins.toJSON probeTargets}
        relabel_configs:
          - source_labels: [ __address__ ]
            target_label: __param_target
          - source_labels: [ module ]
            target_label: __param_module
          - source_labels: [ __param_target ]
            target_label: instance
          - target_label: __address__
            replacement: 127.0.0.1:${toString blackboxPort}
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
            expr: ((node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.10) and ((node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) >= 0.05)
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
            expr: ((node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) < 0.10) and ((node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"}) >= 0.05)
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
            expr: node_systemd_unit_state{state="failed",name=~"(sshd|systemd-networkd|tailscaled|unbound|adguardhome|caddy|promtail|prometheus-node-exporter|qemu-guest-agent|gluetun-vpn-check)\\.service"} == 1
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "Critical systemd unit failed"
              description: "{{ $labels.instance }} unit {{ $labels.name }} is failed."

          - alert: PodmanContainerUnitFailed
            expr: node_systemd_unit_state{state="failed",name=~"podman-.*\\.service",name!~"podman-(prometheus|alertmanager|loki)\\.service"} == 1
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "Container service failed"
              description: "{{ $labels.instance }} unit {{ $labels.name }} is failed."

          - alert: MediaMountDown
            expr: |
              node_systemd_unit_state{
                job="node",
                instance=~"(gw|media|storage)\\.${baseDomain}:${toString nodePort}",
                name="srv-media.mount",
                state="active"
              } == 0
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "/srv/media not mounted"
              description: "{{ $labels.instance }} srv-media.mount is not active."

          - alert: NfsServerDown
            expr: |
              node_systemd_unit_state{
                job="node",
                instance="storage.${baseDomain}:${toString nodePort}",
                name="nfs-server.service",
                state="active"
              } == 0
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "NFS server down"
              description: "storage.${baseDomain} nfs-server.service is not active."
    EOF

    cat > $out/monitoring.yml <<'EOF'
    groups:
      - name: monitoring
        rules:
          - alert: PrometheusConfigReloadFailed
            expr: prometheus_config_last_reload_successful{job="prometheus"} == 0
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "Prometheus config reload failed"
              description: "The last Prometheus configuration reload failed."

          - alert: PrometheusRuleEvaluationFailures
            expr: sum(increase(prometheus_rule_evaluation_failures_total{job="prometheus"}[5m])) > 0
            for: 1m
            labels:
              severity: critical
            annotations:
              summary: "Prometheus rule evaluation failures"
              description: "Prometheus failed to evaluate one or more rules in the last 5m."

          - alert: AlertmanagerNotificationFailures
            expr: sum(increase(alertmanager_notifications_failed_total{job="alertmanager"}[5m])) > 0
            for: 1m
            labels:
              severity: warning
            annotations:
              summary: "Alertmanager notification failures"
              description: "Alertmanager failed to deliver one or more notifications in the last 5m."
    EOF

    cat > $out/proxmox.yml <<'EOF'
    groups:
      - name: proxmox-hwmon
        rules:
          - alert: ProxmoxNvmeHot
            expr: (node_hwmon_temp_celsius{job="node-proxmox",chip="nvme_nvme0",sensor="temp1"} > 75) and (node_hwmon_temp_celsius{job="node-proxmox",chip="nvme_nvme0",sensor="temp1"} <= 85)
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Proxmox NVMe running hot"
              description: "Proxmox NVMe composite temp is {{ $value }}°C for 10m."

          - alert: ProxmoxNvmeCritical
            expr: node_hwmon_temp_celsius{job="node-proxmox",chip="nvme_nvme0",sensor="temp1"} > 85
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Proxmox NVMe critically hot"
              description: "Proxmox NVMe composite temp is {{ $value }}°C for 5m."

          - alert: ProxmoxCpuPackageHot
            expr: (node_hwmon_temp_celsius{job="node-proxmox",chip="platform_coretemp_0",sensor="temp1"} > 80) and (node_hwmon_temp_celsius{job="node-proxmox",chip="platform_coretemp_0",sensor="temp1"} <= 90)
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Proxmox CPU package hot"
              description: "Proxmox CPU package temp is {{ $value }}°C for 10m."

          - alert: ProxmoxCpuPackageCritical
            expr: node_hwmon_temp_celsius{job="node-proxmox",chip="platform_coretemp_0",sensor="temp1"} > 90
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Proxmox CPU package critically hot"
              description: "Proxmox CPU package temp is {{ $value }}°C for 5m."

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
            expr: ((pve_disk_usage_bytes{id=~"^storage/"} / pve_disk_size_bytes{id=~"^storage/"}) > 0.90) and ((pve_disk_usage_bytes{id=~"^storage/"} / pve_disk_size_bytes{id=~"^storage/"}) <= 0.95)
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

          - alert: ProxmoxReplicationFailed
            expr: pve_replication_failed_syncs > 0
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Proxmox replication failures"
              description: "{{ $labels.id }} has failed replication syncs ({{ $value }})."
    EOF

    cat > $out/probes.yml <<'EOF'
    groups:
      - name: probes
        rules:
          - alert: ServiceProbeFailing
            expr: probe_success{job="blackbox-http"} == 0
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Service not responding"
              description: "{{ $labels.service }} ({{ $labels.instance }}) has failed its HTTPS health probe for 5m."

          - alert: ServiceProbesMissing
            expr: absent(probe_success{job="blackbox-http"})
            for: 10m
            labels:
              severity: critical
            annotations:
              summary: "HTTP probes missing"
              description: "No blackbox HTTP probe results; service health is unmonitored."

          - alert: TlsCertExpiringSoon
            expr: (probe_ssl_earliest_cert_expiry{job="blackbox-http"} - time()) < 21 * 86400
            for: 1h
            labels:
              severity: warning
            annotations:
              summary: "TLS certificate expiring soon"
              description: "{{ $labels.service }} certificate expires in {{ $value | humanizeDuration }}; Caddy renewal is probably failing."

          - alert: TlsCertExpiryCritical
            expr: (probe_ssl_earliest_cert_expiry{job="blackbox-http"} - time()) < 7 * 86400
            for: 10m
            labels:
              severity: critical
            annotations:
              summary: "TLS certificate about to expire"
              description: "{{ $labels.service }} certificate expires in {{ $value | humanizeDuration }}."
    EOF

    cat > $out/mounts.yml <<'EOF'
    groups:
      - name: mounts
        rules:
          - alert: MountPathUnhealthy
            expr: homelab_mount_path_healthy == 0
            for: 3m
            labels:
              severity: critical
            annotations:
              summary: "Media path inaccessible"
              description: "{{ $labels.instance }} {{ $labels.scope }} {{ $labels.container }} {{ $labels.path }} cannot be stat'ed/listed (stale handle, I/O error or missing)."

          - alert: MediaNfsNotMounted
            expr: homelab_mount_nfs_mounted == 0
            for: 3m
            labels:
              severity: critical
            annotations:
              summary: "Media NFS mount missing"
              description: "{{ $labels.instance }} {{ $labels.path }} is not an active NFS mount."

          - alert: MountProbeStale
            expr: time() - homelab_mount_probe_last_run_timestamp_seconds > 300
            for: 2m
            labels:
              severity: critical
            annotations:
              summary: "Mount probe not completing"
              description: "{{ $labels.instance }} mount probe last completed {{ $value | humanizeDuration }} ago; NFS may be hung."

          - alert: MountProbeMissing
            expr: absent(homelab_mount_probe_last_run_timestamp_seconds{instance="media.${baseDomain}:${toString nodePort}"})
            for: 10m
            labels:
              severity: warning
            annotations:
              summary: "Mount probe metrics missing"
              description: "vm-media is not exporting mount-probe metrics."
    EOF

    cat > $out/smart.yml <<'EOF'
    # Only interpreted health signals and plain-count attributes are used.
    # Seagate raw_read_error_rate / seek_error_rate / command_timeout raw
    # values are vendor-encoded and deliberately not alerted on.
    groups:
      - name: smart
        rules:
          - alert: SmartDeviceUnhealthy
            expr: smartmon_device_smart_healthy == 0
            for: 15m
            labels:
              severity: critical
            annotations:
              summary: "SMART health check failing"
              description: "{{ $labels.disk }} reports SMART overall-health FAILED."

          - alert: SmartDataStale
            expr: time() - smartmon_smartctl_run > 7200
            for: 30m
            labels:
              severity: warning
            annotations:
              summary: "SMART data stale"
              description: "{{ $labels.disk }} SMART data has not refreshed for {{ $value | humanizeDuration }}."

          - alert: SmartPendingSectors
            expr: smartmon_current_pending_sector_raw_value > 0
            for: 30m
            labels:
              severity: warning
            annotations:
              summary: "Disk has pending sectors"
              description: "{{ $labels.disk }} has {{ $value }} pending (unreadable) sectors."

          - alert: SmartOfflineUncorrectable
            expr: smartmon_offline_uncorrectable_raw_value > 0
            for: 30m
            labels:
              severity: warning
            annotations:
              summary: "Disk has uncorrectable sectors"
              description: "{{ $labels.disk }} has {{ $value }} offline-uncorrectable sectors."

          - alert: SmartReportedUncorrectIncreasing
            expr: delta(smartmon_reported_uncorrect_raw_value[24h]) > 0
            labels:
              severity: warning
            annotations:
              summary: "Disk reporting new uncorrectable errors"
              description: "{{ $labels.disk }} reported {{ $value }} new uncorrectable errors in 24h."

          - alert: SmartReallocationIncreasing
            expr: delta(smartmon_reallocated_sector_ct_raw_value[24h]) > 0 or delta(smartmon_runtime_bad_block_raw_value[24h]) > 0
            labels:
              severity: warning
            annotations:
              summary: "Disk reallocating sectors"
              description: "{{ $labels.disk }} reallocated/bad-block count grew by {{ $value }} in 24h."

          - alert: SmartCrcErrorsIncreasing
            expr: delta(smartmon_udma_crc_error_count_raw_value[1h]) > 0
            labels:
              severity: warning
            annotations:
              summary: "Disk interface CRC errors"
              description: "{{ $labels.disk }} logged {{ $value }} new CRC errors in 1h (cable/backplane)."

          - alert: HddTemperatureHigh
            expr: smartmon_temperature_celsius_raw_value{type="sat"} > 55
            for: 30m
            labels:
              severity: warning
            annotations:
              summary: "Disk running hot"
              description: "{{ $labels.disk }} is at {{ $value }}°C."

          - alert: NvmeCriticalWarning
            expr: nvme_critical_warning > 0
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "NVMe critical warning"
              description: "{{ $labels.device }} critical_warning={{ $value }}."

          - alert: NvmeMediaErrors
            expr: delta(nvme_media_errors_total[24h]) > 0
            labels:
              severity: critical
            annotations:
              summary: "NVMe media/data integrity errors"
              description: "{{ $labels.device }} logged {{ $value }} new media errors in 24h."

          - alert: NvmeSpareLow
            expr: nvme_available_spare_ratio < nvme_available_spare_threshold_ratio
            for: 15m
            labels:
              severity: critical
            annotations:
              summary: "NVMe spare below threshold"
              description: "{{ $labels.device }} available spare is below the vendor threshold."

          - alert: NvmeWearHigh
            expr: nvme_percentage_used_ratio > 0.9
            for: 1h
            labels:
              severity: warning
            annotations:
              summary: "NVMe nearing rated endurance"
              description: "{{ $labels.device }} has used {{ $value | humanizePercentage }} of rated endurance."
    EOF

    # Metric contract for a future backup job (e.g. a node_exporter textfile
    # written after each run):
    #   homelab_backup_last_success_timestamp_seconds{backup="<name>"}
    #   homelab_backup_last_run_success{backup="<name>"}   1 = ok, 0 = failed
    #   homelab_backup_max_age_seconds{backup="<name>"}    schedule + slack
    cat > $out/${if backupAlertsEnabled then "backups.yml" else "backups.yml.disabled"} <<'EOF'
    groups:
      - name: backups
        rules:
          - alert: BackupLastRunFailed
            expr: homelab_backup_last_run_success == 0
            for: 5m
            labels:
              severity: critical
            annotations:
              summary: "Backup failed"
              description: "Backup {{ $labels.backup }} last run failed."

          - alert: BackupMissedOrStale
            expr: (time() - homelab_backup_last_success_timestamp_seconds) > on(instance, backup) homelab_backup_max_age_seconds
            for: 15m
            labels:
              severity: critical
            annotations:
              summary: "Backup overdue"
              description: "Backup {{ $labels.backup }} last succeeded {{ $value | humanizeDuration }} ago (schedule missed)."

          - alert: BackupMetricsMissing
            expr: absent(homelab_backup_last_success_timestamp_seconds)
            for: 1h
            labels:
              severity: critical
            annotations:
              summary: "No backup metrics"
              description: "No backup job is reporting; backups cannot be verified."
    EOF
  '';
in {
  systemd.tmpfiles.rules = lib.mkAfter [ "d ${dataDir} 0750 65534 65534 - -" ];

  virtualisation.oci-containers.containers.prometheus = {
    image = "prom/prometheus:v3.15.0@sha256:efd719c99d83b060d9daefdcf00360461adf279f45ef5391f8d111892118753e";
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
