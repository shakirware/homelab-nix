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
    vault = "/alive";
    notes-api = "/healthcheck";
    notes-files = "/healthcheck";
    yamtrack = "/health/";
    kaneo = "/api/health";
    mealie = "/api/app/about";
    immich = "/api/server/ping";
    seerr = "/api/v1/status";
    audiobookshelf = "/healthcheck";
    sonarr = "/ping";
    radarr = "/ping";
    bazarr = "/api/system/ping";
    prowlarr = "/ping";
    profilarr = "/api/v1/health";
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

  nodeByUpstreamIp = {
    "127.0.0.1" = "gw.${baseDomain}:${toString nodePort}";
    ${ips.gw} = "gw.${baseDomain}:${toString nodePort}";
    ${ips.media} = "media.${baseDomain}:${toString nodePort}";
    ${ips.storage} = "storage.${baseDomain}:${toString nodePort}";
    ${ips.apps} = "apps.${baseDomain}:${toString nodePort}";
    ${ips.sensitive} = "sensitive.${baseDomain}:${toString nodePort}";
    ${ips.monitoring} = "${ips.monitoring}:${toString nodePort}";
    ${ips.proxmox} = "${ips.proxmox}:${toString nodePort}";
  };

  upstreamIp = upstream:
    lib.head (lib.splitString ":"
      (lib.removePrefix "http://" (lib.removePrefix "https://" upstream)));

  probeTargets = map (h:
    let
      name = lib.removeSuffix ".${baseDomain}" h.host;
      node = nodeByUpstreamIp.${upstreamIp h.upstream} or null;
    in {
      targets = [ "https://${h.host}${probePaths.${name} or "/"}" ];
      labels = {
        service = name;
        module = if lib.elem name authRequiredProbes then
          "http_auth_required"
        else
          "http_2xx";
      } // lib.optionalAttrs (node != null) { inherit node; };
    }) config.homelab.webHosts;

  # Metric contract for backup jobs (node_exporter textfile written after
  # each run by nix/modules/backup/metrics.nix and restic-offsite):
  #   homelab_backup_last_success_timestamp_seconds{backup="<name>"}
  #   homelab_backup_last_run_success{backup="<name>"}   1 = ok, 0 = failed
  #   homelab_backup_max_age_seconds{backup="<name>"}    schedule + slack
  #   homelab_backup_repo_bytes{repo="local-<host>"|"b2-<host>"}
  backupAlertsEnabled = true;

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

      # Its own job so the media and NFS rules on job="node" never see it.
      - job_name: "node-ci"
        static_configs:
          - targets: [ "${ips.ci}:${toString nodePort}" ]
            labels:
              host: "vm-ci"

      # Likewise for the release runner (VLAN 31, scraped by address).
      - job_name: "node-release"
        static_configs:
          - targets: [ "${ips.release}:${toString nodePort}" ]
            labels:
              host: "vm-release"

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

      - job_name: "blackbox-icmp"
        metrics_path: /probe
        params:
          module: [ icmp ]
        static_configs:
          - targets: [ "${ips.router_vlan20}" ]
            labels:
              target: "router"
          - targets: [ "1.1.1.1", "9.9.9.9" ]
            labels:
              target: "internet"
        relabel_configs:
          - source_labels: [ __address__ ]
            target_label: __param_target
          - source_labels: [ __param_target ]
            target_label: instance
          - target_label: __address__
            replacement: 127.0.0.1:${toString blackboxPort}

      - job_name: "blackbox-dns"
        metrics_path: /probe
        static_configs:
          - targets: [ "${ips.gw}" ]
            labels:
              module: "dns_external"
          - targets: [ "${ips.gw}" ]
            labels:
              module: "dns_internal"
        relabel_configs:
          - source_labels: [ __address__ ]
            target_label: __param_target
          - source_labels: [ module ]
            target_label: __param_module
          - source_labels: [ __param_target ]
            target_label: instance
          - target_label: __address__
            replacement: 127.0.0.1:${toString blackboxPort}

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
    for f in ${./rules}/*.yml; do
      substitute "$f" "$out/$(basename "$f")" \
        --subst-var-by baseDomain ${lib.escapeShellArg baseDomain} \
        --subst-var-by nodePort ${toString nodePort}
    done
    if grep -n '@[A-Za-z_]*@' $out/*.yml; then
      echo "unsubstituted placeholder in a rule file" >&2
      exit 1
    fi
    ${lib.optionalString (!backupAlertsEnabled) "mv $out/backups.yml $out/backups.yml.disabled"}
  '';
in {
  systemd.tmpfiles.rules = lib.mkAfter [ "d ${dataDir} 0750 65534 65534 - -" ];

  virtualisation.oci-containers.containers.prometheus = {
    image = "prom/prometheus:v3.15.1@sha256:fa3302279710be2f21a8301ec17a8b4f2301fd829bd113839b3b6b02b6f191a2";
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

  homelab.firewall.restrict.${toString port} = [ config.homelab.ips.gw ];
}
