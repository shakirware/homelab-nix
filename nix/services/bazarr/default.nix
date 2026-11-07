{ config, lib, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
  appdataDir = "/srv/appdata/bazarr";
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${appdataDir} 2775 ${config.homelab.ids.user} media - -"
  ];

  virtualisation.oci-containers.containers.bazarr = {
    image = "lscr.io/linuxserver/bazarr:version-v1.6.2@sha256:7ef0e58216900dbce30b123e0eb65f5cb30e36f126de9474acdd2022fb069c54";
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
    };

    # Same /media mount as Sonarr and Radarr, so their paths need no mapping.
    volumes = [
      "${appdataDir}:/config"
      "/srv/media:/media"
    ];

    ports = [ "${bindIp}:6767:6767" ];
  };

  # Ensure media mount exists before start
  systemd.services.podman-bazarr.unitConfig.RequiresMountsFor =
    [ "/srv/media" ];
  systemd.services.podman-bazarr.after =
    [ "network-online.target" "srv-media.mount" "podman-sonarr.service" "podman-radarr.service" ];

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 6767 ];

  homelab.backup = {
    paths = [ "${appdataDir}/config" ];
    sqlite = [ "${appdataDir}/db/bazarr.db" ];
  };
}
