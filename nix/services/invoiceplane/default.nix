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

  dbEnvName = "invoiceplane-db.env";
  appEnvName = "invoiceplane-app.env";
  dbEnvFile = config.sops.templates.${dbEnvName}.path;
  appEnvFile = config.sops.templates.${appEnvName}.path;

  gwIp = config.homelab.ips.gw;

  podman = "${pkgs.podman}/bin/podman";
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
  sops.secrets."invoiceplane/root_password" = { };
  sops.secrets."invoiceplane/db_password" = { };

  # Changing either database password requires coordinated MariaDB grants and
  # application configuration.  Never restart automatically on secret change.
  sops.templates.${dbEnvName} = {
    content = ''
      MARIADB_ROOT_PASSWORD=${config.sops.placeholder."invoiceplane/root_password"}
      MARIADB_PASSWORD=${config.sops.placeholder."invoiceplane/db_password"}
    '';
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ ];
  };

  sops.templates.${appEnvName} = {
    content = ''
      MYSQL_PASSWORD=${config.sops.placeholder."invoiceplane/db_password"}
    '';
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ ];
  };

  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${baseDir}    2775 ${config.homelab.ids.user} media - -"
    "d ${dbDataDir}  2775 ${config.homelab.ids.user} media - -"
    "d ${uploadsDir} 2775 ${config.homelab.ids.user} media - -"
    "d ${cssDir}     2775 ${config.homelab.ids.user} media - -"
    "d ${viewsDir}   2775 ${config.homelab.ids.user} media - -"
  ];

  systemd.services.invoiceplane-prepare = {
    description = "Prepare InvoicePlane directories and runtime configuration";
    wantedBy = [ "multi-user.target" ];
    before = [ "podman-invoiceplane-db.service" "podman-invoiceplane.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = [ pkgs.coreutils pkgs.bash ];

    script = ''
            set -euo pipefail

            install -d -m 2775 -o ${config.homelab.ids.user} -g media \
              ${baseDir} ${dbDataDir} ${uploadsDir} ${cssDir} ${viewsDir}

            # Persist InvoicePlane runtime config (contains encryption key after setup)
            if [ ! -e ${ipconfigPath} ]; then
              touch ${ipconfigPath}
              chown ${config.homelab.ids.user}:media ${ipconfigPath}
              chmod 0664 ${ipconfigPath}
            fi
    '';
  };

  virtualisation.oci-containers.containers.invoiceplane-db = {
    image = "mariadb:12.3@sha256:dd9b303aed4f4890ed09f766d8ca9ddfd176c0c6f6267feff53b3192ec65a979";
    autoStart = true;

    environment = {
      TZ = tz;
      MARIADB_DATABASE = "invoiceplane";
      MARIADB_USER = "invoiceplane";
      MARIADB_AUTO_UPGRADE = "1";
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
    image = "mhzawadi/invoiceplane:1.7.0.1@sha256:85a697d632713e3755cb7b1075126449ba74e4456ebca4b36716c8d9aa86574a";
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
      "${baseDir}/runtime:/var/www/html/runtime"
      "${ipconfigPath}:/var/www/html/ipconfig.php"
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
