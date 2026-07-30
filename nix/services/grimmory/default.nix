{ config, lib, pkgs, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
  port = 6060;

  net = "books-net";
  podman = "${pkgs.podman}/bin/podman";
  bash = "${pkgs.bash}/bin/bash";
  secretFile = "/srv/appdata/grimmory/secrets.env";
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /srv/appdata/grimmory 2775 ${config.homelab.ids.user} media - -"
    "d /srv/appdata/grimmory/data 2775 ${config.homelab.ids.user} media - -"
    "d /srv/appdata/grimmory/mariadb 2775 ${config.homelab.ids.user} media - -"
    "d /srv/appdata/grimmory/mariadb/config 2775 ${config.homelab.ids.user} media - -"
  ];

  systemd.services."podman-network-${net}" = {
    description = "Ensure Podman network ${net} exists";
    wantedBy = [ "multi-user.target" ];
    after = [ "podman.service" ];
    requires = [ "podman.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''
        ${bash} -lc "${podman} network inspect ${net} >/dev/null 2>&1 || ${podman} network create ${net}"
      '';
    };
  };

  systemd.services.grimmory-secrets = {
    description = "Create persistent Grimmory database credentials";
    after = [ "systemd-tmpfiles-setup.service" ];
    before = [ "podman-grimmory-db.service" "podman-grimmory.service" ];

    path = [ pkgs.coreutils pkgs.openssl ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -euo pipefail
      umask 077

      if [ ! -s ${secretFile} ]; then
        db_password="$(openssl rand -hex 32)"
        root_password="$(openssl rand -hex 32)"

        cat > ${secretFile} <<ENV
DATABASE_PASSWORD=$db_password
MYSQL_PASSWORD=$db_password
MYSQL_ROOT_PASSWORD=$root_password
ENV
      fi

      chown root:root ${secretFile}
      chmod 0600 ${secretFile}
    '';
  };

  virtualisation.oci-containers.containers.grimmory-db = {
    image = "lscr.io/linuxserver/mariadb:11.4.5";
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
      MYSQL_DATABASE = "grimmory";
      MYSQL_USER = "grimmory";
    };

    environmentFiles = [ secretFile ];
    volumes = [ "/srv/appdata/grimmory/mariadb/config:/config" ];
    extraOptions = [
      "--network=${net}"
      "--network-alias=grimmory-db"
    ];
  };

  systemd.services.podman-grimmory-db = {
    wants = [ "network-online.target" ];
    after = [ "podman-network-${net}.service" "grimmory-secrets.service" ];
    requires = [ "podman-network-${net}.service" "grimmory-secrets.service" ];
  };

  systemd.services.grimmory-db-ready = {
    description = "Wait for Grimmory MariaDB to accept connections";
    after = [ "podman-grimmory-db.service" ];
    requires = [ "podman-grimmory-db.service" ];
    before = [ "podman-grimmory.service" ];

    path = [ pkgs.coreutils pkgs.podman ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -euo pipefail

      for _ in $(seq 1 60); do
        if ${podman} exec grimmory-db mariadb-admin ping -h 127.0.0.1 --silent >/dev/null 2>&1; then
          exit 0
        fi
        sleep 2
      done

      echo "Grimmory MariaDB did not become ready" >&2
      exit 1
    '';
  };

  virtualisation.oci-containers.containers.grimmory = {
    image = "ghcr.io/grimmory-tools/grimmory:v3.2.4";
    autoStart = true;

    environment = {
      USER_ID = puid;
      GROUP_ID = pgid;
      TZ = tz;
      DATABASE_URL = "jdbc:mariadb://grimmory-db:3306/grimmory";
      DATABASE_USERNAME = "grimmory";
      SWAGGER_ENABLED = "false";
      DISK_TYPE = "LOCAL";
      JAVA_TOOL_OPTIONS = "-Xms256m -Xmx1536m";
    };

    environmentFiles = [ secretFile ];

    volumes = [
      "/srv/appdata/grimmory/data:/app/data"
      "/srv/media/books/library:/books"
      "/srv/media/books/bookdrop:/bookdrop"
    ];

    ports = [ "${bindIp}:${toString port}:${toString port}" ];

    extraOptions = [ "--network=${net}" ];
  };

  systemd.services.podman-grimmory = {
    wants = [ "network-online.target" ];
    after = [
      "podman-network-${net}.service"
      "grimmory-secrets.service"
      "grimmory-db-ready.service"
      "network-online.target"
      "srv-media.mount"
    ];
    requires = [
      "podman-network-${net}.service"
      "grimmory-secrets.service"
      "grimmory-db-ready.service"
    ];
    unitConfig.RequiresMountsFor = [ "/srv/media" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  networking.firewall.interfaces."podman4" = {
    allowedUDPPorts = lib.mkAfter [ 53 ];
    allowedTCPPorts = lib.mkAfter [ 53 ];
  };
}
