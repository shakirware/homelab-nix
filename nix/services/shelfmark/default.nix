{ config, lib, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  port = 8084;
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /srv/appdata/shelfmark 2775 ${config.homelab.ids.user} media - -"
  ];

  virtualisation.oci-containers.containers.shelfmark = {
    image = "ghcr.io/calibrain/shelfmark:v1.6.2@sha256:0b400a5d58951b35bfede3d9943b632551259c31e130316fe56c5cc0e2e4faea";
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
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
