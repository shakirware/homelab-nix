{ config, lib, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
in {
  virtualisation.oci-containers.containers.radarr = {
    image = "lscr.io/linuxserver/radarr:version-6.4.4.10685@sha256:fc0ae3c50f8128b97e84381903ec8d6845c3a569641cb7117c124376cccb57c1";
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
      # Host headers Radarr answers to (loopback and its own hostname are
      # always allowed): Caddy, and vm-media's IP, which Prowlarr, Seerr,
      # Cleanuparr, Profilarr and Homepage use.
      RADARR__SERVER__ALLOWEDHOSTS =
        "radarr.${config.homelab.baseDomain},${config.homelab.ips.media}";
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

  homelab.backup = {
    paths = [ "/srv/appdata/radarr/config.xml" ];
    sqlite = [ "/srv/appdata/radarr/radarr.db" ];
  };
}
