{ config, lib, pkgs, home, iot, ... }:

let
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

in {

  environment.systemPackages = with pkgs; [
    intel-media-driver
    libva-vdpau-driver
  ];

  virtualisation.oci-containers.containers.jellyfin = {
    image = "lscr.io/linuxserver/jellyfin:12.4ubu2604-ls59@sha256:2f708001387aa9853e744a4a4d572d9970927c479c56d6c9e199f789c5173535";
    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = config.time.timeZone;
    };

    volumes = [ "/srv/appdata/jellyfin:/config" "/srv/media:/data" ];

    ports = [ "0.0.0.0:8096:8096" "0.0.0.0:7359:7359/udp" ];

    extraOptions = [
      # The default 10 s ends in SIGKILL mid-shutdown.
      "--stop-timeout=60"
      "--device=/dev/dri/renderD128:/dev/dri/renderD128"
      "--device=/dev/dri/card0:/dev/dri/card0"
    ];

  };

  homelab.containers.jellyfin.media = true;

  homelab.firewall.restrict = let
    clients = [ config.homelab.ips.gw home.cidr iot.cidr ];
  in {
    "8096" = clients;
    "7359/udp" = clients;
  };

  homelab.backup = {
    paths = [ "/srv/appdata/jellyfin" ];
    exclude = [
      "/srv/appdata/jellyfin/cache"
      "/srv/appdata/jellyfin/log"
      "/srv/appdata/jellyfin/data/metadata"
      "/srv/appdata/jellyfin/data/transcodes"
      "/srv/appdata/jellyfin/data/data/introskipper"
      "/srv/appdata/jellyfin/data/data/jellyfin.db"
    ];
    sqlite = [ "/srv/appdata/jellyfin/data/data/jellyfin.db" ];
  };
}
