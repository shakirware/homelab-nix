{ config, lib, ... }:

let
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  port = 3030;
in {
  virtualisation.oci-containers.containers.readmeabook = {
    image = "ghcr.io/kikootwo/readmeabook:1.2.13@sha256:b789e19d8cb888e572094c1b790cf4f57c2249a4a7fd1fab8f55633c79f196cd";
    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = config.time.timeZone;
      UMASK = "002";
      PUBLIC_URL = "https://readmeabook.${config.homelab.baseDomain}";
    };

    volumes = [
      "/srv/appdata/readmeabook/config:/app/config"
      "/srv/appdata/readmeabook/cache:/app/cache"
      "/srv/appdata/readmeabook/pgdata:/var/lib/postgresql/data"
      "/srv/appdata/readmeabook/redis:/var/lib/redis"
      "/srv/downloads:/data"
      "/srv/media/audiobooks:/media"
    ];

  };

  systemd.services.podman-readmeabook = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "srv-media.mount" "srv-downloads.mount" ];
    unitConfig.RequiresMountsFor = [ "/srv/media" "/srv/downloads" ];
  };

  homelab.containers.readmeabook = {
    publish.${toString port} = [ config.homelab.ips.gw ];
    appdata = [
      "/srv/appdata/readmeabook"
      "/srv/appdata/readmeabook/config"
      "/srv/appdata/readmeabook/cache"
      "/srv/appdata/readmeabook/pgdata"
      "/srv/appdata/readmeabook/redis"
    ];
  };

  homelab.backup = {
    paths = [ "/srv/appdata/readmeabook/config" ];
    postgres = [{
      container = "readmeabook";
      db = "readmeabook";
      user = "postgres";
      execUser = "postgres";
    }];
  };
}
