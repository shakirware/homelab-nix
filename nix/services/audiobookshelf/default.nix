{ config, lib, ... }:

let
  port = 13378;
in {
  virtualisation.oci-containers.containers.audiobookshelf = {
    image = "ghcr.io/advplyr/audiobookshelf:2.37.2@sha256:b897c33f05972fb1bf484f7487bc878fa91ec8691335c1db6e2929c3a7658efa";
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
