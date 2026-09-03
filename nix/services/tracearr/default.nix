{ config, lib, pkgs, ... }:

let
  tz = "Europe/London";

  hostPort = 3003;
  bindIp = "0.0.0.0";

  net = "tracearr-net";

  subnet = "10.91.0.0/24";
  gateway = "10.91.0.1";
  dbIp = "10.91.0.2";
  redisIp = "10.91.0.3";
  appIp = "10.91.0.4";

  timescaleVol = "tracearr_timescale_data";
  redisVol = "tracearr_redis_data";

  podman = "${pkgs.podman}/bin/podman";
  bash = "${pkgs.bash}/bin/bash";

  seq = "${pkgs.coreutils}/bin/seq";
  sleep = "${pkgs.coreutils}/bin/sleep";

  waitDb = pkgs.writeShellScript "tracearr-wait-db" ''
    set -euo pipefail

    echo "tracearr: waiting for PostgreSQL..."

    for i in $(${seq} 1 30); do
      if ${podman} exec tracearr-db \
        pg_isready -U tracearr -d tracearr -t 1 >/dev/null 2>&1; then
        exit 0
      fi

      ${sleep} 1
    done

    echo "tracearr: PostgreSQL did not become ready" >&2
    exit 1
  '';

  gwIp = config.homelab.ips.gw;

  envName = "tracearr.env";
  dbEnvName = "tracearr-db.env";
in {
  sops.secrets."tracearr/jwt_secret" = { };
  sops.secrets."tracearr/cookie_secret" = { };
  sops.secrets."tracearr/db_password" = { };

  sops.templates.${envName} = {
    content = ''
      NODE_ENV=production
      PORT=3000
      HOST=0.0.0.0
      TZ=${tz}

      DATABASE_URL=postgres://tracearr:${
        config.sops.placeholder."tracearr/db_password"
      }@${dbIp}:5432/tracearr

      REDIS_URL=redis://${redisIp}:6379

      JWT_SECRET=${config.sops.placeholder."tracearr/jwt_secret"}
      COOKIE_SECRET=${config.sops.placeholder."tracearr/cookie_secret"}

      # Optional (matches upstream defaults)
      CORS_ORIGIN=*
      LOG_LEVEL=info
    '';
    owner = "root";
    group = "root";
    mode = "0400";
    # This template includes the database password.  Rotation is a coordinated
    # PostgreSQL migration and must never trigger an ordinary restart.
    restartUnits = [ ];
  };

  sops.templates.${dbEnvName} = {
    content = ''
      POSTGRES_PASSWORD=${config.sops.placeholder."tracearr/db_password"}
    '';
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ ];
  };

  systemd.services."podman-network-${net}" = {
    description = "Ensure podman network ${net} exists";
    wantedBy = [ "multi-user.target" ];
    after = [ "podman.service" ];
    requires = [ "podman.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''
        ${bash} -lc "${podman} network inspect ${net} >/dev/null 2>&1 || ${podman} network create --subnet ${subnet} --gateway ${gateway} ${net}"
      '';
    };
  };

  virtualisation.oci-containers.containers = {
    tracearr-db = {
      image = "timescale/timescaledb:latest-pg16@sha256:289d55704b1b3ee8263cd3805c6930f9cd54506835a8f19f9b85dad17d5c5a8a";
      autoStart = true;

      cmd = [
        "postgres"
        "-c"
        "timescaledb.max_tuples_decompressed_per_dml_transaction=0"
        "-c"
        "max_locks_per_transaction=4096"
      ];

      environment = {
        POSTGRES_USER = "tracearr";
        POSTGRES_DB = "tracearr";
      };

      environmentFiles = [ config.sops.templates.${dbEnvName}.path ];

      volumes = [ "${timescaleVol}:/var/lib/postgresql/data" ];

      extraOptions = [
        "--network=${net}"
        "--ip=${dbIp}"
        "--name=tracearr-db"
        "--shm-size=512m"
        "--ulimit=nofile=65536:65536"
      ];
    };

    tracearr-redis = {
      image = "redis:8-alpine@sha256:4eec4565e45aa0b3966554c866bc73211e281b0b3d89fe9a33c982e6faca809d";
      autoStart = true;

      cmd = [ "redis-server" "--appendonly" "yes" ];

      volumes = [ "${redisVol}:/data" ];

      extraOptions =
        [ "--network=${net}" "--ip=${redisIp}" "--name=tracearr-redis" ];
    };

    tracearr = {
      image = "ghcr.io/connorgallopo/tracearr:latest@sha256:586569ea2970530be861fb7d7f842d42efd9151d91c0c528b008b381030705dd";
      autoStart = true;

      environmentFiles = [ config.sops.templates.${envName}.path ];

      ports = [ "${bindIp}:${toString hostPort}:3000" ];

      extraOptions = [ "--network=${net}" "--ip=${appIp}" "--name=tracearr" ];
    };
  };

  systemd.services.podman-tracearr-db = {
    after = [ "podman-network-${net}.service" "podman.service" ];
    requires = [ "podman-network-${net}.service" "podman.service" ];
  };

  systemd.services.podman-tracearr-redis = {
    after = [ "podman-network-${net}.service" "podman.service" ];
    requires = [ "podman-network-${net}.service" "podman.service" ];
  };

  systemd.services.podman-tracearr = {
    after = [
      "podman-network-${net}.service"
      "podman-tracearr-db.service"
      "podman-tracearr-redis.service"
      "podman.service"
    ];
    requires = [
      "podman-network-${net}.service"
      "podman-tracearr-db.service"
      "podman-tracearr-redis.service"
      "podman.service"
    ];

    serviceConfig.ExecStartPre = lib.mkAfter [ waitDb ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ hostPort ];

}
