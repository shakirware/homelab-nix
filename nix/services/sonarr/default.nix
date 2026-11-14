{ config, lib, ... }:

let
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;
in {
  virtualisation.oci-containers.containers.sonarr = {
    image = "lscr.io/linuxserver/sonarr:version-4.0.20.3014@sha256:889dcc58c6aea859033985894b519b2e6b1e55d92527ed123f9f52e42ae7c97b";
    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = config.time.timeZone;
    };

    volumes = [
      "/srv/appdata/sonarr:/config"
      "/srv/downloads:/downloads"
      "/srv/media:/media"
    ];
  };

  homelab.containers.sonarr = {
    publish."8989" = [ config.homelab.ips.gw ];
    media = true;
  };

  homelab.backup = {
    paths = [ "/srv/appdata/sonarr/config.xml" ];
    sqlite = [ "/srv/appdata/sonarr/sonarr.db" ];
  };
}
