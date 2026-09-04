{ lib, ... }:

let
  tz = "Europe/London";
  puid = "1000";
  pgid = "1001";
in {
  virtualisation.oci-containers.containers.prowlarr = {
    image = "lscr.io/linuxserver/prowlarr:version-2.3.5.5327@sha256:2489c6dbaf11e3a6d71aeb2e6980d04193d4af611aa7064a974851222fd41722";
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
    };

    volumes = [ "/srv/appdata/prowlarr:/config" ];

    ports = [ ];

    extraOptions = [ "--network=container:gluetun" ];
  };

  systemd.services.podman-prowlarr = {
    after = [ "podman-gluetun.service" "podman.service" ];
    requires = [ "podman-gluetun.service" "podman.service" ];
  };

}
