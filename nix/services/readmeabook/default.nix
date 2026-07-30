{ config, lib, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
  port = 3030;
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /srv/appdata/readmeabook 2775 ${config.homelab.ids.user} media - -"
    "d /srv/appdata/readmeabook/config 2775 ${config.homelab.ids.user} media - -"
    "d /srv/appdata/readmeabook/cache 2775 ${config.homelab.ids.user} media - -"
    "d /srv/appdata/readmeabook/pgdata 2775 ${config.homelab.ids.user} media - -"
    "d /srv/appdata/readmeabook/redis 2775 ${config.homelab.ids.user} media - -"
  ];

  virtualisation.oci-containers.containers.readmeabook = {
    image = "ghcr.io/kikootwo/readmeabook:1.2.1";
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
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

    ports = [ "${bindIp}:${toString port}:${toString port}" ];

  };

  systemd.services.podman-readmeabook = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "srv-media.mount" "srv-downloads.mount" ];
    unitConfig.RequiresMountsFor = [ "/srv/media" "/srv/downloads" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];
}
