{ config, lib, ... }:

let
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  appdataDir = "/srv/appdata/bazarr";
in {
  virtualisation.oci-containers.containers.bazarr = {
    image = "lscr.io/linuxserver/bazarr:version-v1.6.2@sha256:946dc8c5bb5331418eac60050cf40a63cb8f66ac039841dda493870e3559799c";
    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = config.time.timeZone;
    };

    # Same /media mount as Sonarr and Radarr, so their paths need no mapping.
    volumes = [
      "${appdataDir}:/config"
      "/srv/media:/media"
    ];
  };

  homelab.containers.bazarr = {
    publish."6767" = [ config.homelab.ips.gw ];
    media = true;
    appdata = appdataDir;
  };

  systemd.services.podman-bazarr.after =
    [ "podman-sonarr.service" "podman-radarr.service" ];

  homelab.backup = {
    paths = [ "${appdataDir}/config" ];
    sqlite = [ "${appdataDir}/db/bazarr.db" ];
  };
}
