{ lib, ... }:

let
  tz = "Europe/London";
  puid = "1000";
  pgid = "1001";
in {
  virtualisation.oci-containers.containers.qbittorrent = {
    image = "lscr.io/linuxserver/qbittorrent:version-5.1.4-r1@sha256:95114034a7f74672b76f795f6938921b0ca795f85b59b48691035dc66714f34c";
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

}
