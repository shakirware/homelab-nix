{ config, lib, pkgs, ... }:

let
  tz = "Europe/London";

  apiPort = 3000;
  filesPort = 3125;
  webPort = 3002;

  bindIp = "0.0.0.0";

  baseDomain = config.homelab.baseDomain;

  apiHost = "notes-api.${baseDomain}";
  apiUrl = "https://${apiHost}";

  filesHost = "notes-files.${baseDomain}";

  baseDir = "/srv/appdata/standardnotes";
  logsDir = "${baseDir}/logs";
  uploadsDir = "${baseDir}/uploads";

  envFile = "${baseDir}/.env";
  mysqlEnvFile = "${baseDir}/mysql.env";
  localstackBootstrap = "${baseDir}/localstack_bootstrap.sh";

  podman = "${pkgs.podman}/bin/podman";
  snNet = "podman";

  podmanIfaces = ''{ "podman0", "cni-podman0" }'';

  serverImage =
    "docker.io/standardnotes/server:0d82819cba9694bc9fb5a3fa53e2dbeda05d1242";
  webImage = "docker.io/standardnotes/web:latest";

  localstackImage = "docker.io/localstack/localstack:3.0";
  mysqlImage = "docker.io/library/mysql:8";
  redisImage = "docker.io/library/redis:6.0-alpine";

  mysqlVol = "standardnotes-mysql";
  redisVol = "standardnotes-redis";

  waitScript = pkgs.writeShellScript "standardnotes-wait-deps" ''
    set -euo pipefail

    if [ ! -f "${mysqlEnvFile}" ]; then
      echo "standardnotes: missing ${mysqlEnvFile}" >&2
      exit 1
    fi

    DB_PASS="$(grep '^MYSQL_ROOT_PASSWORD=' "${mysqlEnvFile}" | cut -d= -f2- || true)"
    if [ -z "$DB_PASS" ]; then
      echo "standardnotes: MYSQL_ROOT_PASSWORD not found in ${mysqlEnvFile}" >&2
      exit 1
    fi

    echo "standardnotes: waiting for mysql..."
    for i in $(seq 1 150); do
      if ${podman} exec db_self_hosted mysqladmin ping -uroot -p"$DB_PASS" --silent >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
    ${podman} exec db_self_hosted mysqladmin ping -uroot -p"$DB_PASS" --silent >/dev/null

    echo "standardnotes: waiting for redis..."
    for i in $(seq 1 150); do
      if ${podman} exec cache_self_hosted redis-cli ping 2>/dev/null | grep -q PONG; then
        break
      fi
      sleep 2
    done
    ${podman} exec cache_self_hosted redis-cli ping | grep -q PONG

    echo "standardnotes: db + cache ready"
  '';
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${baseDir} 0700 root root - -"
    "d ${logsDir} 0750 root root - -"
    "d ${uploadsDir} 0750 root root - -"
  ];

  systemd.services.standardnotes-config = {
    description =
      "Prepare Standard Notes (env + secrets + localstack bootstrap)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = [ pkgs.coreutils pkgs.bash pkgs.curl pkgs.openssl pkgs.gnugrep ];

    script = ''
            set -euo pipefail

            install -d -m 0700 ${baseDir}
            install -d -m 0750 ${logsDir} ${uploadsDir}

            if [ ! -f ${localstackBootstrap} ]; then
              curl -fsSL https://raw.githubusercontent.com/standardnotes/server/main/docker/localstack_bootstrap.sh \
                -o ${localstackBootstrap}
              chmod 0755 ${localstackBootstrap}
            fi

            if [ ! -f ${envFile} ]; then
              DB_PASSWORD="$(openssl rand -hex 12)"
              AUTH_JWT_SECRET="$(openssl rand -hex 32)"
              AUTH_SERVER_ENCRYPTION_SERVER_KEY="$(openssl rand -hex 32)"
              VALET_TOKEN_SECRET="$(openssl rand -hex 32)"

              cat > ${envFile} <<EOF
      DB_HOST=db
      DB_PORT=3306
      DB_USERNAME=std_notes_user
      DB_PASSWORD=$DB_PASSWORD
      DB_DATABASE=standard_notes_db
      DB_TYPE=mysql

      REDIS_PORT=6379
      REDIS_HOST=cache
      CACHE_TYPE=redis

      AUTH_JWT_SECRET=$AUTH_JWT_SECRET
      AUTH_SERVER_ENCRYPTION_SERVER_KEY=$AUTH_SERVER_ENCRYPTION_SERVER_KEY
      VALET_TOKEN_SECRET=$VALET_TOKEN_SECRET

      # Important: allow cookies across notes-api / notes / notes-files
      COOKIE_DOMAIN=${baseDomain}

      PUBLIC_FILES_SERVER_URL=https://${filesHost}
      EOF
              chmod 0600 ${envFile}
            fi

            if [ ! -f ${mysqlEnvFile} ]; then
              DB_PASSWORD="$(grep '^DB_PASSWORD=' ${envFile} | cut -d= -f2-)"
              cat > ${mysqlEnvFile} <<EOF
      MYSQL_ROOT_PASSWORD=$DB_PASSWORD
      MYSQL_PASSWORD=$DB_PASSWORD
      EOF
              chmod 0600 ${mysqlEnvFile}
            fi
    '';
  };

  virtualisation.oci-containers.containers = {
    server_self_hosted = {
      image = serverImage;
      autoStart = true;

      environment = { TZ = tz; };
      environmentFiles = [ envFile ];

      ports = [
        "${bindIp}:${toString apiPort}:3000"
        "${bindIp}:${toString filesPort}:3104"
      ];

      volumes = [
        "${logsDir}:/var/lib/server/logs"
        "${uploadsDir}:/opt/server/packages/files/dist/uploads"
      ];

      extraOptions = [ "--network=${snNet}" ];
    };

    localstack_self_hosted = {
      image = localstackImage;
      autoStart = true;

      environment = {
        SERVICES = "sns,sqs";
        HOSTNAME_EXTERNAL = "localstack";
        LS_LOG = "warn";
      };

      volumes = [
        "${localstackBootstrap}:/etc/localstack/init/ready.d/localstack_bootstrap.sh:ro"
      ];

      extraOptions = [ "--network=${snNet}" "--network-alias=localstack" ];
    };

    db_self_hosted = {
      image = mysqlImage;
      autoStart = true;

      environment = {
        MYSQL_DATABASE = "standard_notes_db";
        MYSQL_USER = "std_notes_user";
      };

      environmentFiles = [ mysqlEnvFile ];
      volumes = [ "${mysqlVol}:/var/lib/mysql" ];

      extraOptions = [ "--network=${snNet}" "--network-alias=db" ];
    };

    cache_self_hosted = {
      image = redisImage;
      autoStart = true;

      volumes = [ "${redisVol}:/data" ];

      extraOptions = [ "--network=${snNet}" "--network-alias=cache" ];
    };

    standardnotes_web = {
      image = webImage;
      autoStart = true;

      environment = {
        TZ = tz;

        # Key fix: stop the web app defaulting to api.standardnotes.com
        DEFAULT_SYNC_SERVER = apiUrl;
      };

      ports = [ "${bindIp}:${toString webPort}:80" ];
    };
  };

  systemd.services.podman-server_self_hosted.serviceConfig = {
    Restart = lib.mkForce "on-failure";
    RestartSec = lib.mkForce "5s";
    ExecStartPre = lib.mkAfter [ waitScript ];
  };
  systemd.services.podman-db_self_hosted.serviceConfig = {
    Restart = lib.mkForce "on-failure";
    RestartSec = lib.mkForce "5s";
  };
  systemd.services.podman-cache_self_hosted.serviceConfig = {
    Restart = lib.mkForce "on-failure";
    RestartSec = lib.mkForce "5s";
  };
  systemd.services.podman-localstack_self_hosted.serviceConfig = {
    Restart = lib.mkForce "on-failure";
    RestartSec = lib.mkForce "5s";
  };
  systemd.services.podman-standardnotes_web.serviceConfig = {
    Restart = lib.mkForce "on-failure";
    RestartSec = lib.mkForce "5s";
  };

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.firewall.allowedTCPPorts =
    lib.mkAfter [ apiPort filesPort webPort ];

  networking.firewall.filterForward = true;

  networking.firewall.extraInputRules = lib.mkAfter ''
    ip saddr 192.168.1.0/24 tcp dport { ${toString apiPort}, ${
      toString filesPort
    }, ${toString webPort} } accept
    tcp dport { ${toString apiPort}, ${toString filesPort}, ${
      toString webPort
    } } drop
  '';

  networking.nftables.tables."nixos-fw" = {
    family = "inet";
    content = lib.mkAfter ''
      chain forward-allow {
        # allow established/related (safe)
        ct state established,related accept

        # allow forwarding to/from podman bridges (netavark + legacy cni)
        iifname { "podman0", "cni-podman0" } accept
        oifname { "podman0", "cni-podman0" } accept
      }
    '';
  };
}
