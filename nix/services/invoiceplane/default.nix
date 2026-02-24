{ config, lib, pkgs, ... }:

let
  tz = "Europe/London";

  bindIp = "0.0.0.0";
  port = 8088;

  baseDomain = config.homelab.baseDomain;
  publicHost = "invoice.${baseDomain}";
  publicUrl = "https://${publicHost}";

  baseDir = "/srv/appdata/invoiceplane";
  dbDataDir = "${baseDir}/mariadb";
  uploadsDir = "${baseDir}/uploads";
  cssDir = "${baseDir}/custom-css";
  viewsDir = "${baseDir}/custom-views";
  ipconfigPath = "${baseDir}/ipconfig.php";

  dbEnvFile = "${baseDir}/db.env";
  appEnvFile = "${baseDir}/app.env";

  gwIp = config.homelab.ips.gw;

  podman = "${pkgs.podman}/bin/podman";
  openssl = "${pkgs.openssl}/bin/openssl";
  grep = "${pkgs.gnugrep}/bin/grep";
  cut = "${pkgs.coreutils}/bin/cut";
  seq = "${pkgs.coreutils}/bin/seq";
  sleep = "${pkgs.coreutils}/bin/sleep";

  waitDb = pkgs.writeShellScript "invoiceplane-wait-db" ''
    set -euo pipefail

    if [ ! -f "${dbEnvFile}" ]; then
      echo "invoiceplane: missing ${dbEnvFile}" >&2
      exit 1
    fi

    ROOT_PASS="$(${grep} '^MARIADB_ROOT_PASSWORD=' "${dbEnvFile}" | ${cut} -d= -f2- || true)"
    if [ -z "$ROOT_PASS" ]; then
      echo "invoiceplane: MARIADB_ROOT_PASSWORD missing in ${dbEnvFile}" >&2
      exit 1
    fi

    echo "invoiceplane: waiting for MariaDB..."
    for i in $(${seq} 1 90); do
      if ${podman} exec invoiceplane-db mariadb-admin ping -uroot "-p$ROOT_PASS" --silent >/dev/null 2>&1; then
        exit 0
      fi
      ${sleep} 2
    done

    ${podman} exec invoiceplane-db mariadb-admin ping -uroot "-p$ROOT_PASS" --silent >/dev/null
  '';
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${baseDir}    2775 ${config.homelab.ids.user} media - -"
    "d ${dbDataDir}  2775 ${config.homelab.ids.user} media - -"
    "d ${uploadsDir} 2775 ${config.homelab.ids.user} media - -"
    "d ${cssDir}     2775 ${config.homelab.ids.user} media - -"
    "d ${viewsDir}   2775 ${config.homelab.ids.user} media - -"
  ];

  systemd.services.invoiceplane-prepare = {
    description = "Prepare InvoicePlane directories and generated secrets";
    wantedBy = [ "multi-user.target" ];
    before = [ "podman-invoiceplane-db.service" "podman-invoiceplane.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = [ pkgs.coreutils pkgs.bash pkgs.openssl pkgs.gnugrep ];

    script = ''
            set -euo pipefail

            install -d -m 2775 -o ${config.homelab.ids.user} -g media \
              ${baseDir} ${dbDataDir} ${uploadsDir} ${cssDir} ${viewsDir}

            # Generate DB secrets once and persist on disk
            if [ ! -f ${dbEnvFile} ]; then
              DB_PASS="$(${openssl} rand -hex 18)"
              ROOT_PASS="$(${openssl} rand -hex 18)"
              cat > ${dbEnvFile} <<EOF
      MARIADB_ROOT_PASSWORD=$ROOT_PASS
      MARIADB_PASSWORD=$DB_PASS
      EOF
              chmod 0600 ${dbEnvFile}
            fi

            # App only needs MYSQL_PASSWORD
            if [ ! -f ${appEnvFile} ]; then
              DB_PASS="$(${grep} '^MARIADB_PASSWORD=' ${dbEnvFile} | cut -d= -f2-)"
              cat > ${appEnvFile} <<EOF
      MYSQL_PASSWORD=$DB_PASS
      EOF
              chmod 0600 ${appEnvFile}
            fi

            # Persist InvoicePlane runtime config (contains encryption key after setup)
            if [ ! -e ${ipconfigPath} ]; then
              touch ${ipconfigPath}
              chown ${config.homelab.ids.user}:media ${ipconfigPath}
              chmod 0664 ${ipconfigPath}
            fi
    '';
  };

  virtualisation.oci-containers.containers.invoiceplane-db = {
    image = "mariadb:10.11";
    autoStart = true;

    environment = {
      TZ = tz;
      MARIADB_DATABASE = "invoiceplane";
      MARIADB_USER = "invoiceplane";
    };

    environmentFiles = [ dbEnvFile ];

    volumes = [ "${dbDataDir}:/var/lib/mysql" ];

    extraOptions = [
      "--network=podman"
      "--network-alias=invoiceplane-db"
      "--name=invoiceplane-db"
    ];
  };

  virtualisation.oci-containers.containers.invoiceplane = {
    # Pin for reproducibility; move to newer tag after testing
    image = "mhzawadi/invoiceplane:1.7.0.0";
    autoStart = true;

    environment = {
      TZ = tz;
      MYSQL_HOST = "invoiceplane-db";
      MYSQL_PORT = "3306";
      MYSQL_USER = "invoiceplane";
      MYSQL_DB = "invoiceplane";

      IP_URL = publicUrl;
      REMOVE_INDEXPHP = "true";

      # Trust your reverse proxy for forwarded headers
      PROXY_IPS = gwIp;
    };

    environmentFiles = [ appEnvFile ];

    volumes = [
      "${uploadsDir}:/var/www/html/uploads"
      "${cssDir}:/var/www/html/assets/core/css"
      "${viewsDir}:/var/www/html/application/views"
      "/srv/appdata/invoiceplane/runtime:/var/www/html/runtime"
    ];

    ports = [ "${bindIp}:${toString port}:80" ];

    extraOptions = [ "--network=podman" "--name=invoiceplane" ];
  };

  systemd.services."podman-invoiceplane-db" = {
    after = [
      "podman.service"
      "invoiceplane-prepare.service"
      "network-online.target"
    ];
    requires = [ "podman.service" "invoiceplane-prepare.service" ];
    wants = [ "network-online.target" ];
  };

  systemd.services."podman-invoiceplane" = {
    after = [
      "podman.service"
      "invoiceplane-prepare.service"
      "podman-invoiceplane-db.service"
      "network-online.target"
    ];
    requires = [
      "podman.service"
      "invoiceplane-prepare.service"
      "podman-invoiceplane-db.service"
    ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce "5s";
      ExecStartPre = lib.mkAfter [ waitDb ];
    };
  };

}
