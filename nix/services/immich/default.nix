{ config, lib, pkgs, ... }:

let

  port = 2283;
  bindIp = "0.0.0.0";

  net = "immich-net";

  subnet = "10.93.0.0/24";
  gateway = "10.93.0.1";
  dbIp = "10.93.0.2";
  redisIp = "10.93.0.3";
  mlIp = "10.93.0.4";
  serverIp = "10.93.0.5";

  photosDir = config.homelab.nfsMount.mountPoint;
  appDir = "/srv/appdata/immich";
  user = config.homelab.ids.user;

  pgVol = "immich_pg_data";
  modelVol = "immich_model_cache";

  podman = "${pkgs.podman}/bin/podman";
  bash = "${pkgs.bash}/bin/bash";

  seq = "${pkgs.coreutils}/bin/seq";
  sleep = "${pkgs.coreutils}/bin/sleep";

  waitDb = pkgs.writeShellScript "immich-wait-db" ''
    set -euo pipefail

    echo "immich: waiting for PostgreSQL..."

    for i in $(${seq} 1 60); do
      if ${podman} exec immich-db \
        pg_isready -U postgres -d immich -t 1 >/dev/null 2>&1; then
        exit 0
      fi

      ${sleep} 1
    done

    echo "immich: PostgreSQL did not become ready" >&2
    exit 1
  '';

  gwIp = config.homelab.ips.gw;

  envName = "immich.env";
  dbEnvName = "immich-db.env";
in {
  sops.secrets."immich/db_password" = { };

  sops.templates.${envName} = {
    content = ''
      TZ=${config.time.timeZone}
      DB_HOSTNAME=immich-db
      DB_USERNAME=postgres
      DB_DATABASE_NAME=immich
      DB_PASSWORD=${config.sops.placeholder."immich/db_password"}
      REDIS_HOSTNAME=immich-redis
    '';
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ ];
  };

  sops.templates.${dbEnvName} = {
    content = ''
      POSTGRES_PASSWORD=${config.sops.placeholder."immich/db_password"}
    '';
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ ];
  };

  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${appDir} 0750 ${user} media - -"
    "d ${appDir}/thumbs 0750 ${user} media - -"
    "d ${appDir}/encoded-video 0750 ${user} media - -"
  ];

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
    immich-db = {
      image =
        "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
      environment = {
        POSTGRES_USER = "postgres";
        POSTGRES_DB = "immich";
        POSTGRES_INITDB_ARGS = "--data-checksums";
      };

      environmentFiles = [ config.sops.templates.${dbEnvName}.path ];

      volumes = [ "${pgVol}:/var/lib/postgresql/data" ];

      extraOptions = [
        "--network=${net}"
        "--ip=${dbIp}"
        "--name=immich-db"
        "--shm-size=128m"
        "--stop-timeout=60"
      ];
    };

    immich-redis = {
      image =
        "docker.io/valkey/valkey:9@sha256:c123e3715db63d06d4ad6964884037aa0d5d4d703939b9929954112889708e1d";
      extraOptions = [ "--network=${net}" "--ip=${redisIp}" "--name=immich-redis" ];
    };

    immich-machine-learning = {
      image =
        "ghcr.io/immich-app/immich-machine-learning:v3.3.6@sha256:14367bfb374b8576ddf49abd67c5ca0190a4c7fcf6303cdad65d7f7bf1a50bc2";
      environment = {
        TZ = config.time.timeZone;
        MACHINE_LEARNING_MODEL_TTL = "300";
      };

      volumes = [ "${modelVol}:/cache" ];

      extraOptions = [
        "--network=${net}"
        "--ip=${mlIp}"
        "--name=immich-machine-learning"
        "--cpus=2"
        "--memory=3g"
      ];
    };

    immich-server = {
      image =
        "ghcr.io/immich-app/immich-server:v3.3.6@sha256:e1981983b1c13f6024b57d72e7ecae3342eed1581201ab09fb248932d86c593a";
      environmentFiles = [ config.sops.templates.${envName}.path ];

      volumes = [
        "${photosDir}:/data"
        "${appDir}/thumbs:/data/thumbs"
        "${appDir}/encoded-video:/data/encoded-video"
        "/etc/localtime:/etc/localtime:ro"
      ];

      ports = [ "${bindIp}:${toString port}:2283" ];

      extraOptions = [
        "--network=${net}"
        "--ip=${serverIp}"
        "--name=immich-server"
        "--stop-timeout=60"
      ];
    };
  };

  systemd.services.podman-immich-db = {
    after = [ "podman-network-${net}.service" "podman.service" ];
    requires = [ "podman-network-${net}.service" "podman.service" ];
  };

  systemd.services.podman-immich-redis = {
    after = [ "podman-network-${net}.service" "podman.service" ];
    requires = [ "podman-network-${net}.service" "podman.service" ];
  };

  systemd.services.podman-immich-machine-learning = {
    after = [ "podman-network-${net}.service" "podman.service" ];
    requires = [ "podman-network-${net}.service" "podman.service" ];
    serviceConfig.CPUWeight = 50;
  };

  systemd.services.podman-immich-server = {
    after = [
      "podman-network-${net}.service"
      "podman-immich-db.service"
      "podman-immich-redis.service"
      "podman.service"
    ];
    requires = [
      "podman-network-${net}.service"
      "podman-immich-db.service"
      "podman-immich-redis.service"
      "podman.service"
    ];
    wants = [ "podman-immich-machine-learning.service" ];

    serviceConfig = {
      ExecStartPre = [ waitDb ];
      CPUWeight = 50;
    };
  };

  networking.firewall.extraInputRules = lib.mkAfter ''
    ip saddr ${subnet} ip daddr ${gateway} meta l4proto { tcp, udp } th dport 53 accept
  '';

  homelab.firewall.restrict.${toString port} = [ gwIp ];

  homelab.backup.postgres = [{
    container = "immich-db";
    db = "immich";
    user = "postgres";
    dumpArgs = [ "-Z0" ];
  }];

  assertions = [{
    assertion =
      !(lib.any (p: lib.hasPrefix photosDir p) config.homelab.backup.paths);
    message =
      "${photosDir} must stay out of homelab.backup.paths: that repository is copied to B2.";
  }];
}
