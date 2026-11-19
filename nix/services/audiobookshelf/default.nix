{ config, lib, ... }:

let
  port = 13378;
in {
  virtualisation.oci-containers.containers.audiobookshelf = {
    image = "ghcr.io/advplyr/audiobookshelf:2.38.0@sha256:60064c23f32fd9099fd39e82c5132c51701d1221135bbca04cd099b589e1edc3";
    volumes = [
      "/srv/media/audiobooks:/audiobooks"
      "/srv/appdata/audiobookshelf/metadata:/metadata"
      "/srv/appdata/audiobookshelf/config:/config"
    ];

  };

  systemd.services.podman-audiobookshelf = {
    wants = [ "network-online.target" ];
  };

  homelab.containers.audiobookshelf = {
    media = true;
    publish.${toString port} = { sources = [ config.homelab.ips.gw ]; to = 80; };
    appdata = [
      "/srv/appdata/audiobookshelf"
      "/srv/appdata/audiobookshelf/config"
      "/srv/appdata/audiobookshelf/metadata"
    ];
  };

  homelab.backup = {
    paths = [
      "/srv/appdata/audiobookshelf/config"
      "/srv/appdata/audiobookshelf/metadata"
    ];
    exclude = [ "/srv/appdata/audiobookshelf/config/absdatabase.sqlite" ];
    sqlite = [ "/srv/appdata/audiobookshelf/config/absdatabase.sqlite" ];
  };
}
