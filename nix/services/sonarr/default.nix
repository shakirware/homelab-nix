{ config, lib, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
in {
  virtualisation.oci-containers.containers.sonarr = {
    image = "lscr.io/linuxserver/sonarr:version-4.0.20.3014@sha256:3b8c947d7fa173f70e40047d2c8d02835fb8416aeb5ae36def57d9ad15e2f906";
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
