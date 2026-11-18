{ config, lib, ... }:

let
  port = 11011;

  appdataDir = "/srv/appdata/cleanuparr";

  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  gwIp = config.homelab.ips.gw;
in {
  virtualisation.oci-containers.containers.cleanuparr = {
    image = "ghcr.io/cleanuparr/cleanuparr:2.11.1@sha256:923c2fe435e22fc58d261bacd2d6bbd8eb1ba3f95358803a8e4d3287ffd919d3";
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
