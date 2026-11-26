{ config, lib, ... }:

let
  puid = "1000";
  pgid = "1001";
in {
  virtualisation.oci-containers.containers.prowlarr = {
    image = "lscr.io/linuxserver/prowlarr:version-3.1.0.5799@sha256:2806c9b763810589c42157730d547c293639e55c7610e9f5069314854639ec48";
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
