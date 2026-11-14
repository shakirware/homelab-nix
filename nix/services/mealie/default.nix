{ config, lib, ... }:

let

  port = 9000;

  dataDir = "/srv/appdata/mealie";

  uid = toString config.homelab.ids.uid;
  gid = toString config.homelab.ids.mediaGid;

  gwIp = config.homelab.ips.gw;
in {
  virtualisation.oci-containers.containers.mealie = {
    image = "ghcr.io/mealie-recipes/mealie:v3.30.0@sha256:90f83da6f3ab0a421efc827118a556168573930105f13fa3321768f42163d784";
    environment = {
      TZ = config.time.timeZone;

      PUID = uid;
      PGID = gid;

      BASE_URL = "https://mealie.${config.homelab.baseDomain}";
      ALLOW_SIGNUP = "false";
      DB_ENGINE = "sqlite";
    };

    volumes = [
      "${dataDir}:/app/data"
    ];

    extraOptions = [
      "--memory=1g"
    ];
  };

  systemd.services.podman-mealie = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  homelab.containers.mealie = {
    publish.${toString port} = { sources = [ gwIp ]; to = 9000; };
    appdata = dataDir;
  };

  homelab.backup = {
    paths = [ dataDir ];
    exclude = [
      "${dataDir}/mealie.db"
      "${dataDir}/mealie.db-*"
    ];
    sqlite = [ "${dataDir}/mealie.db" ];
  };
}
