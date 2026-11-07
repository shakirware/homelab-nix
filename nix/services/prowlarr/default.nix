{ config, lib, ... }:

let
  tz = "Europe/London";
  puid = "1000";
  pgid = "1001";
in {
  virtualisation.oci-containers.containers.prowlarr = {
    image = "lscr.io/linuxserver/prowlarr:version-2.7.0.5723@sha256:431d7efebcef466e56adaa40a7a2fa2b0e85159a037b8bf465eaadbf0cf5bedf";
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
      # Host headers Prowlarr answers to (loopback and its own hostname are
      # always allowed): Caddy, and vm-media's IP via gluetun's published
      # port, which Sonarr, Radarr, ReadMeABook, Shelfmark and Homepage use.
      PROWLARR__SERVER__ALLOWEDHOSTS =
        "prowlarr.${config.homelab.baseDomain},${config.homelab.ips.media}";
      # FlareSolverr's cf_clearance cookie only works from the IP that solved
      # the challenge, which is gluetun's IPv4 exit; over the tunnel's IPv6
      # exit Cloudflare rejects it.
      DOTNET_SYSTEM_NET_DISABLEIPV6 = "1";
    };

    volumes = [ "/srv/appdata/prowlarr:/config" ];

    ports = [ ];

    extraOptions = [ "--network=container:gluetun" ];
  };

  systemd.services.podman-prowlarr = {
    after = [ "podman-gluetun.service" "podman.service" ];
    requires = [ "podman-gluetun.service" "podman.service" ];
  };

  homelab.backup = {
    paths = [ "/srv/appdata/prowlarr/config.xml" ];
    sqlite = [ "/srv/appdata/prowlarr/prowlarr.db" ];
  };
}
