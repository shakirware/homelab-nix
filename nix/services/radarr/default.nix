{ config, lib, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
in {
  virtualisation.oci-containers.containers.radarr = {
    image = "lscr.io/linuxserver/radarr:version-6.0.4.10291";
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
    };

    volumes = [
      "/srv/appdata/radarr:/config"
      "/srv/downloads:/downloads"
      "/srv/media:/media"
    ];

    ports = [ "${bindIp}:7878:7878" ];
  };

  # Ensure media mount exists before start
  systemd.services.podman-radarr.unitConfig.RequiresMountsFor =
    [ "/srv/media" ];
  systemd.services.podman-radarr.after =
    [ "network-online.target" "srv-media.mount" ];

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 7878 ];
}
