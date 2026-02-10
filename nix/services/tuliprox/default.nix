{ config, lib, ... }:

let
  tz = "Europe/London";

  uid = toString config.homelab.ids.uid;
  gid = toString config.homelab.ids.mediaGid;

  port = 8901;

  appdataDir = "/srv/appdata/tuliprox";
  cfgDir = "${appdataDir}/config";
  dataDir = "${appdataDir}/data";
  backupDir = "${appdataDir}/backup";
  downloadsDir = "${appdataDir}/downloads";

  gwIp = config.homelab.ips.gw;
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${appdataDir}    2775 ${config.homelab.ids.user} media - -"
    "d ${cfgDir}        2775 ${config.homelab.ids.user} media - -"
    "d ${dataDir}       2775 ${config.homelab.ids.user} media - -"
    "d ${backupDir}     2775 ${config.homelab.ids.user} media - -"
    "d ${downloadsDir}  2775 ${config.homelab.ids.user} media - -"
  ];

  virtualisation.oci-containers.containers.tuliprox = {
    image = "ghcr.io/euzu/tuliprox:latest";
    autoStart = true;

    cmd = [
      "/app/tuliprox"
      "-p"
      "/app/config"
      "-s"
      "-a"
      "/app/config/api-proxy.yml"
    ];

    ports = [ ];

    extraOptions = [
      "--network=container:gluetun"
      "--user=${uid}:${gid}"
      "--workdir=/app/data"
    ];

    environment = { TZ = tz; };

    volumes = [
      "${cfgDir}:/app/config:ro"
      "${dataDir}:/app/data"
      "${backupDir}:/app/backup"
      "${downloadsDir}:/app/downloads"
    ];
  };

  systemd.services."podman-tuliprox" = {
    after = [ "podman-gluetun.service" "podman.service" ];
    requires = [ "podman-gluetun.service" "podman.service" ];
  };
}
