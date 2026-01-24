{ config, lib, pkgs, ... }:

let
  tz = "Europe/London";

  bindIp = "0.0.0.0";
  port = 5984;

  baseDir = "/srv/appdata/obsidian-livesync";
  dataDir = "${baseDir}/couchdb-data";
  localIniPath = "${baseDir}/local.ini";

  couchdbUid = "5984";
  couchdbGid = "5984";

  localIni = ''
    [couchdb]
    single_node = true
    max_document_size = 50000000

    [chttpd]
    enable_cors = true
    require_valid_user = true
    max_http_request_size = 4294967296

    [chttpd_auth]
    require_valid_user = true
    authentication_redirect = /_utils/session.html

    [httpd]
    WWW-Authenticate = Basic realm="couchdb"
    enable_cors = true

    [cors]
    origins = app://obsidian.md,capacitor://localhost,http://localhost
    credentials = true
    headers = accept,authorization,content-type,origin,referer,x-couchdb-vhost,x-requested-with
    methods = GET,PUT,POST,HEAD,DELETE,OPTIONS
    max_age = 3600
  '';
in {
  homelab.secrets.envTemplates."couchdb-obsidian" = {
    env = {
      COUCHDB_USER = "obsidian/couchdb_user";
      COUCHDB_PASSWORD = "obsidian/couchdb_password";
    };
  };

  systemd.services.couchdb-prepare = {
    description = "Prepare CouchDB dirs and config for Obsidian LiveSync";
    wantedBy = [ "multi-user.target" ];
    before = [ "podman-couchdb.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils pkgs.bash ];
    script = ''
            set -euo pipefail

            install -d -m 0755 ${baseDir}
            install -d -m 0750 -o ${couchdbUid} -g ${couchdbGid} ${dataDir}

            cat > ${localIniPath} <<'EOF'
      ${localIni}
      EOF

            chown ${couchdbUid}:${couchdbGid} ${localIniPath}
            chmod 0640 ${localIniPath}
    '';
  };

  virtualisation.oci-containers.containers.couchdb = {
    image = "couchdb:3";
    autoStart = true;

    autoRemoveOnStop = lib.mkForce false;

    environment = { TZ = tz; };
    environmentFiles = [ config.sops.templates."couchdb-obsidian".path ];

    volumes = [
      "${dataDir}:/opt/couchdb/data"
      "${localIniPath}:/opt/couchdb/etc/local.ini"
    ];

    ports = [ "${bindIp}:${toString port}:${toString port}" ];
  };

  systemd.services.podman-couchdb = {
    after =
      [ "podman.service" "network-online.target" "couchdb-prepare.service" ];
    requires = [ "podman.service" "couchdb-prepare.service" ];
    wants = [ "network-online.target" ];
  };

  networking.nftables.tables."obsidian-couchdb" = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority 0; policy accept;
        tcp dport ${toString port} jump couchdb_guard
      }

      chain couchdb_guard {
        ct state established,related accept
        iifname "lo" accept
        ip saddr ${config.homelab.ips.gw} accept
        drop
      }
    '';
  };
}
