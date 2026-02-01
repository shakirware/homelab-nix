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
    image = "lscr.io/linuxserver/jellyfin:version-10.11.5ubu2404";
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
    };

    volumes = [ "/srv/appdata/jellyfin:/config" "/srv/media:/data" ];

    ports = [ "${bindIp}:8096:8096" "${bindIp}:7359:7359/udp" ];

    extraOptions = [
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
}
