{ config, lib, ... }:

let
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;
in {
  virtualisation.oci-containers.containers.radarr = {
    image = "lscr.io/linuxserver/radarr:version-7.0.3.10918@sha256:044788f5508b7f67a3e0368cdd142c77c4d4cd5aec2efaba53e1a68b6b6231e7";
    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = config.time.timeZone;
      # Host headers Radarr answers to (loopback and its own hostname are
      # always allowed): Caddy, and vm-media's IP, which Prowlarr, Seerr,
      # Cleanuparr, Profilarr and Homepage use.
      RADARR__SERVER__ALLOWEDHOSTS =
        "radarr.${config.homelab.baseDomain},${config.homelab.ips.media}";
    };

    volumes = [
      "/srv/appdata/radarr:/config"
      "/srv/downloads:/downloads"
      "/srv/media:/media"
    ];
  };

  homelab.containers.radarr = {
    publish."7878" = [ config.homelab.ips.gw ];
    media = true;
  };

  homelab.backup = {
    paths = [ "/srv/appdata/radarr/config.xml" ];
    sqlite = [ "/srv/appdata/radarr/radarr.db" ];
  };
}
