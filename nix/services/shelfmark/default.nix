{ config, lib, ... }:

let
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  port = 8084;
in {
  homelab.containers.shelfmark.appdata = "/srv/appdata/shelfmark";

  virtualisation.oci-containers.containers.shelfmark = {
    image = "ghcr.io/calibrain/shelfmark:v1.7.0@sha256:6544e02595271b0267b9acda58fa7f3db6f14942bece51b7aadfe4000cf34f1c";
    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = config.time.timeZone;
      FLASK_PORT = toString port;
      INGEST_DIR = "/books";
      SEARCH_MODE = "universal";
      SHOW_COMBINED_SELECTOR = "false";
      BOOKS_OUTPUT_MODE = "folder";
      FILE_ORGANIZATION = "none";
      HARDLINK_TORRENTS = "false";
    };

    volumes = [
      "/srv/appdata/shelfmark:/config"
      "/srv/media/books/bookdrop:/books"
      "/srv/downloads:/data"
    ];

    extraOptions = [ "--network=container:gluetun" ];
  };

  systemd.services.podman-shelfmark = {
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "srv-media.mount"
      "srv-downloads.mount"
      "podman-gluetun.service"
    ];
    requires = [ "podman-gluetun.service" ];
    unitConfig.RequiresMountsFor = [ "/srv/media" "/srv/downloads" ];
  };

  homelab.firewall.restrict.${toString port} = [ config.homelab.ips.gw ];

  homelab.backup = {
    paths = [ "/srv/appdata/shelfmark" ];
    exclude = [ "/srv/appdata/shelfmark/users.db" ];
    sqlite = [ "/srv/appdata/shelfmark/users.db" ];
  };
}
