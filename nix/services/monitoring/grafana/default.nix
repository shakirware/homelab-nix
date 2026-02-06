{ config, lib, pkgs, ... }:

let
  ips = config.homelab.ips;
  base = config.homelab.baseDomain;

  port = 3000;
  dataDir = "/srv/appdata/grafana";

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

    cat > $out/dashboards/dashboards.yml <<'EOF'
    apiVersion: 1
    providers:
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
    image = "grafana/grafana:11.2.0";
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
}
