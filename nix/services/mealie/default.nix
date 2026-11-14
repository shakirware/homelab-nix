{ config, lib, ... }:

let

  port = 9000;

  dataDir = "/srv/appdata/mealie";

  uid = toString config.homelab.ids.uid;
  gid = toString config.homelab.ids.mediaGid;

  gwIp = config.homelab.ips.gw;
in {
  virtualisation.oci-containers.containers.mealie = {
    image = "ghcr.io/mealie-recipes/mealie:v3.31.0@sha256:97e21ac96e9a8d1ee15aaf558ba3f14998936b9d6f334e40ebb4c6c2127dc12f";
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
