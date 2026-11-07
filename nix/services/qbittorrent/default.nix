{ lib, ... }:

let
  tz = "Europe/London";
  puid = "1000";
  pgid = "1001";
in {
  virtualisation.oci-containers.containers.qbittorrent = {
    image = "lscr.io/linuxserver/qbittorrent:version-5.3.0_v2.1.2@sha256:05c1454f9a32967affc1f34f67f8cc0cc57dd805dca45489fe797095a6286556";
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;

      WEBUI_PORT = "8080";
    };

    volumes = [ "/srv/appdata/qbittorrent:/config" "/srv/downloads:/data" ];

    ports = [ ];

    extraOptions = [ "--network=container:gluetun" ];
  };

  systemd.services.podman-qbittorrent = {
    after = [ "podman-gluetun.service" "podman.service" ];
    requires = [ "podman-gluetun.service" "podman.service" ];
  };

  homelab.backup.paths = [ "/srv/appdata/qbittorrent" ];
}
