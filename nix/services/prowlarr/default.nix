{ config, lib, ... }:

let
  puid = "1000";
  pgid = "1001";
in {
  virtualisation.oci-containers.containers.prowlarr = {
    image = "lscr.io/linuxserver/prowlarr:version-3.0.2.5780@sha256:45117ba8439e2337a92ffe38a451a4dafc0be771754d05d88cdf102419d09646";
    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = config.time.timeZone;
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
  };

  homelab.containers.prowlarr.vpn = true;

  homelab.backup = {
    paths = [ "/srv/appdata/prowlarr/config.xml" ];
    sqlite = [ "/srv/appdata/prowlarr/prowlarr.db" ];
  };
}
