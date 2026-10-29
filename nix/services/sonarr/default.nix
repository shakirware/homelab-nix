{ config, lib, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
in {
  virtualisation.oci-containers.containers.sonarr = {
    image = "lscr.io/linuxserver/sonarr:version-4.0.20.3014@sha256:889dcc58c6aea859033985894b519b2e6b1e55d92527ed123f9f52e42ae7c97b";
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
    };

    volumes = [
      "/srv/appdata/sonarr:/config"
      "/srv/downloads:/downloads"
      "/srv/media:/media"
    ];

    ports = [ "${bindIp}:8989:8989" ];
  };

  # Ensure media mount exists before start
  systemd.services.podman-sonarr.unitConfig.RequiresMountsFor =
    [ "/srv/media" ];
  systemd.services.podman-sonarr.after =
    [ "network-online.target" "srv-media.mount" ];

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 8989 ];

  homelab.backup = {
    paths = [ "/srv/appdata/sonarr/config.xml" ];
    sqlite = [ "/srv/appdata/sonarr/sonarr.db" ];
  };
}
