{ config, lib, ... }:

let
  port = 11011;

  appdataDir = "/srv/appdata/cleanuparr";

  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  gwIp = config.homelab.ips.gw;
in {
  virtualisation.oci-containers.containers.cleanuparr = {
    image = "ghcr.io/cleanuparr/cleanuparr:2.11.0@sha256:1898c3219e7e7ecaf9fcb8474691b6d67d56d0798b01b85690975bae14df11b5";
    environment = {
      TZ = config.time.timeZone;
      PORT = toString port;
      PUID = puid;
      PGID = pgid;
      UMASK = "022";
    };

    # /data is deliberate: qBittorrent sees /srv/downloads as /data in your stack.
    volumes = [
      "${appdataDir}:/config"
      "/srv/downloads:/data"
    ];
  };

  systemd.services.podman-cleanuparr = {
    after = [ "podman.service" "network-online.target" ];
    requires = [ "podman.service" ];
    wants = [ "network-online.target" ];
  };

  homelab.containers.cleanuparr = {
    publish.${toString port} = {
      sources = [ gwIp ];
      localContainers = false;
    };
    appdata = appdataDir;
  };

  # events.db is an activity log and is left out.
  homelab.backup = {
    paths = [ appdataDir ];
    exclude = [ "${appdataDir}/logs" "${appdataDir}/*.db" ];
    sqlite = [ "${appdataDir}/cleanuparr.db" "${appdataDir}/users.db" ];
  };
}
