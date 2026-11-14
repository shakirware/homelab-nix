{ config, lib, pkgs, home, iot, ... }:

let
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
in {

  environment.systemPackages = with pkgs; [
    intel-media-driver
    libva-vdpau-driver
  ];

  virtualisation.oci-containers.containers.jellyfin = {
    image = "lscr.io/linuxserver/jellyfin:12.2ubu2604-ls55@sha256:38f6ad3bcd487c82933ede7e32d74ab8712fffcff9e87b16dd2e245ab37130f8";
    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = config.time.timeZone;
    };

    volumes = [ "/srv/appdata/jellyfin:/config" "/srv/media:/data" ];

    ports = [ "${bindIp}:8096:8096" "${bindIp}:7359:7359/udp" ];

    extraOptions = [
      # The default 10 s ends in SIGKILL mid-shutdown.
      "--stop-timeout=60"
      "--device=/dev/dri/renderD128:/dev/dri/renderD128"
      "--device=/dev/dri/card0:/dev/dri/card0"
    ];

  };

  systemd.services.podman-jellyfin.unitConfig.RequiresMountsFor =
    [ "/srv/media" ];
  systemd.services.podman-jellyfin.after =
    [ "network-online.target" "srv-media.mount" ];

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
