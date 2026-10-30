{ config, lib, pkgs, ... }:

let
  ips = config.homelab.ips;
  base = config.homelab.baseDomain;

  port = 3000;
  dataDir = "/srv/appdata/grafana";

  # Provisioned read-only beside the hand-made dashboards.
  backupsDashboard = let
    stat = { id, title, expr, legend, x, y, w, h, fieldConfig }: {
      inherit id title fieldConfig;
      type = "stat";
      gridPos = { inherit x y w h; };
      targets = [{ refId = "A"; inherit expr; legendFormat = legend; instant = true; }];
      options = {
        colorMode = "background";
        graphMode = "none";
        textMode = "value_and_name";
        reduceOptions = { calcs = [ "lastNotNull" ]; fields = ""; values = false; };
      };
    };
    perBackup = "{{instance}} {{backup}}";
  in builtins.toJSON {
    uid = "homelab-backups";
    title = "Backups";
    tags = [ "backups" ];
    timezone = "browser";
    schemaVersion = 39;
    refresh = "5m";
    time = { from = "now-30d"; to = "now"; };
    panels = [
      (stat {
        id = 1;
        title = "Time since last successful backup";
        expr = "time() - homelab_backup_last_success_timestamp_seconds";
        legend = perBackup;
        x = 0; y = 0; w = 16; h = 8;
        fieldConfig.defaults = {
          unit = "s";
          thresholds = {
            mode = "absolute";
            steps = [
              { color = "green"; value = null; }
              { color = "orange"; value = 86400; }
              { color = "red"; value = 93600; }
            ];
          };
        };
      })
      (stat {
        id = 2;
        title = "Last run";
        expr = "homelab_backup_last_run_success";
        legend = perBackup;
        x = 16; y = 0; w = 8; h = 8;
        fieldConfig.defaults = {
          mappings = [{
            type = "value";
            options = {
              "0" = { text = "Failed"; color = "red"; };
              "1" = { text = "OK"; color = "green"; };
            };
          }];
          thresholds = {
            mode = "absolute";
            steps = [
              { color = "red"; value = null; }
              { color = "green"; value = 1; }
            ];
          };
        };
      })
      {
        id = 3;
        title = "B2 usage (free tier 10 GB)";
        type = "gauge";
        gridPos = { x = 0; y = 8; w = 8; h = 8; };
        targets = [{
          refId = "A";
          expr = ''sum(homelab_backup_repo_bytes{repo=~"b2-.*"})'';
          instant = true;
        }];
        fieldConfig.defaults = {
          unit = "decbytes";
          min = 0;
          max = 10000000000;
          thresholds = {
            mode = "absolute";
            steps = [
              { color = "green"; value = null; }
              { color = "orange"; value = 6000000000; }
              { color = "red"; value = 8000000000; }
            ];
          };
        };
      }
      {
        id = 4;
        title = "Repository size";
        type = "timeseries";
        gridPos = { x = 8; y = 8; w = 16; h = 8; };
        targets = [{
          refId = "A";
          expr = "homelab_backup_repo_bytes";
          legendFormat = "{{repo}}";
        }];
        fieldConfig.defaults.unit = "decbytes";
        options.legend = { displayMode = "table"; placement = "right"; calcs = [ "lastNotNull" ]; };
      }
    ];
  };

  provisioningDir = pkgs.runCommand "grafana-provisioning" { } ''
    mkdir -p $out/datasources $out/dashboards

    cat > $out/datasources/datasources.yml <<'EOF'
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://127.0.0.1:9090
        isDefault: true
      - name: Loki
        type: loki
        access: proxy
        url: http://127.0.0.1:3100
    EOF

    mkdir -p $out/dashboards-nix
    cp ${pkgs.writeText "backups.json" backupsDashboard} $out/dashboards-nix/backups.json

    cat > $out/dashboards/dashboards.yml <<'EOF'
    apiVersion: 1
    providers:
      - name: nix
        orgId: 1
        folder: Homelab
        type: file
        disableDeletion: true
        allowUiUpdates: false
        options:
          path: /etc/grafana/provisioning/dashboards-nix
      - name: default
        orgId: 1
        folder: Homelab
        type: file
        disableDeletion: false
        editable: true
        options:
          path: /var/lib/grafana/dashboards
    EOF
  '';
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${dataDir} 0750 472 472 - -"
    "d ${dataDir}/dashboards 0750 472 472 - -"
  ];

  virtualisation.oci-containers.containers.grafana = {
    image = "grafana/grafana:13.2.4@sha256:dbbc38ea21103cefb50396340cd88afec779c7e070b0a7bf5a75b4ce46651d3f";
    autoStart = true;

    environment = {
      GF_SERVER_HTTP_PORT = toString port;
      GF_SERVER_DOMAIN = "grafana.${base}";
      GF_SERVER_ROOT_URL = "https://grafana.${base}";
      GF_SECURITY_DISABLE_INITIAL_ADMIN_CREATION = "false";
      GF_USERS_ALLOW_SIGN_UP = "false";
    };

    volumes = [
      "${dataDir}:/var/lib/grafana"
      "${provisioningDir}:/etc/grafana/provisioning:ro"
      "${dataDir}/dashboards:/var/lib/grafana/dashboards"
    ];

    ports = [ ];

    extraOptions = [ "--network=host" "--name=grafana" ];
  };

  systemd.services.podman-grafana = {
    after = [ "podman.service" ];
    requires = [ "podman.service" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  # Hand-made dashboards live in grafana.db; plugins re-download.
  homelab.backup.sqlite = [ "${dataDir}/grafana.db" ];
}
