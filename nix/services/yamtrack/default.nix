{ config, lib, pkgs, ... }:

let

  bindIp = "0.0.0.0";
  port = 8000;

  appdataDir = "/srv/appdata/yamtrack";
  dbDir = "${appdataDir}/db";
  redisDir = "${appdataDir}/redis";
  secretName = "yamtrack.env";
  secretFile = config.sops.templates.${secretName}.path;

  net = "yamtrack-net";

  podman = "${pkgs.podman}/bin/podman";
  bash = "${pkgs.bash}/bin/bash";

  uid = toString config.homelab.ids.uid;
  gid = toString config.homelab.ids.mediaGid;

  gwIp = config.homelab.ips.gw;
in {
  sops.secrets."yamtrack/secret" = { };

  sops.templates.${secretName} = {
    content = ''
      SECRET=${config.sops.placeholder."yamtrack/secret"}
    '';
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ "podman-yamtrack.service" ];
  };

  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${appdataDir} 2775 ${config.homelab.ids.user} media - -"
    "d ${dbDir} 2775 ${config.homelab.ids.user} media - -"
    "d ${redisDir} 2775 ${config.homelab.ids.user} media - -"
  ];

  # Dedicated network for Yamtrack <-> Redis.
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

  virtualisation.oci-containers.containers.yamtrack-redis = {
    image = "redis:8-alpine@sha256:0bf6577d7774e592b29d093e3ac9390eb91e13d72c21e506afce736de5e0eeb0";
    volumes = [
      "${redisDir}:/data"
    ];

    extraOptions = [
      "--network=${net}"
      "--network-alias=redis"
      "--user=${uid}:${gid}"
    ];
  };

  systemd.services.podman-yamtrack-redis = {
    after = [
      "podman-network-${net}.service"
      "network-online.target"
    ];

    requires = [
      "podman-network-${net}.service"
    ];

    wants = [ "network-online.target" ];
  };

  virtualisation.oci-containers.containers.yamtrack = {
    image = "ghcr.io/fuzzygrim/yamtrack:0.26.3@sha256:78497b454b2b52d3b1062f6fd238351d714cff0895db4369e49ace36f4622e75";
    environment = {
      TZ = config.time.timeZone;

      PUID = uid;
      PGID = gid;

      REDIS_URL = "redis://redis:6379";

      # Sets both Django ALLOWED_HOSTS and trusted CSRF origins.
      URLS = "https://yamtrack.${config.homelab.baseDomain}";

      # Leave enabled for first account creation.
      # Disable after creating your account.
      REGISTRATION = "False";

      DEBUG = "False";
    };

    environmentFiles = [
      secretFile
    ];

    volumes = [
      "${dbDir}:/yamtrack/db"
    ];

    ports = [
      "${bindIp}:${toString port}:8000"
    ];

    extraOptions = [
      "--network=${net}"
      "--no-healthcheck"
    ];
  };

  systemd.services.podman-yamtrack = {
    after = [
      "podman-network-${net}.service"
      "podman-yamtrack-redis.service"
      "network-online.target"
    ];

    requires = [
      "podman-network-${net}.service"
      "podman-yamtrack-redis.service"
    ];

    wants = [ "network-online.target" ];
  };

  networking.firewall.interfaces."podman3" = {
  allowedUDPPorts = [ 53 ];
  allowedTCPPorts = [ 53 ];
};

  homelab.firewall.restrict.${toString port} = [ gwIp ];

  homelab.backup.sqlite = [ "${dbDir}/db.sqlite3" ];
}
