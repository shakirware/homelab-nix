{ config, lib, ... }:

let
  bindIp = "0.0.0.0";
  port = 13378;
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /srv/appdata/audiobookshelf 2775 ${config.homelab.ids.user} media - -"
    "d /srv/appdata/audiobookshelf/config 2775 ${config.homelab.ids.user} media - -"
    "d /srv/appdata/audiobookshelf/metadata 2775 ${config.homelab.ids.user} media - -"
  ];

  virtualisation.oci-containers.containers.audiobookshelf = {
    image = "ghcr.io/advplyr/audiobookshelf:2.36.0";
    autoStart = true;

    volumes = [
      "/srv/media/audiobooks:/audiobooks"
      "/srv/appdata/audiobookshelf/metadata:/metadata"
      "/srv/appdata/audiobookshelf/config:/config"
    ];

    ports = [ "${bindIp}:${toString port}:80" ];

  };

  systemd.services.podman-audiobookshelf = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "srv-media.mount" ];
    unitConfig.RequiresMountsFor = [ "/srv/media" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];
}
