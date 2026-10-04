{ config, lib, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
  port = 8084;
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /srv/appdata/shelfmark 2775 ${config.homelab.ids.user} media - -"
  ];

  virtualisation.oci-containers.containers.shelfmark = {
    image = "ghcr.io/calibrain/shelfmark:v1.4.0@sha256:4ef757349c3c7a7d90ba95b1e2a46ce4dd460a4776efbcf2aa1b1c476e7d5de5";
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

    ports = [ "${bindIp}:${toString port}:${toString port}" ];

  };

  systemd.services.podman-shelfmark = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "srv-media.mount" "srv-downloads.mount" ];
    unitConfig.RequiresMountsFor = [ "/srv/media" "/srv/downloads" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];
}
