{ config, lib, pkgs, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
in {

  environment.systemPackages = with pkgs; [
    intel-media-driver
    libva-vdpau-driver
  ];

  virtualisation.oci-containers.containers.jellyfin = {
    image = "lscr.io/linuxserver/jellyfin:12.4ubu2604-ls58@sha256:b7eabe1f098f4e850bfd63d6721369117195410a471db1a41748ab768b81a639";
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
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

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 8096 ];
  networking.firewall.allowedUDPPorts = lib.mkAfter [ 7359 ];

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
