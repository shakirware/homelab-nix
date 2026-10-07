{ lib, ... }:

let tz = "Europe/London";
in {
  virtualisation.oci-containers.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:v3.5.2@sha256:c80ae007ce2ccdcd217a12426e4f039ef763ff90738c808d38810c3e59323767";
    autoStart = true;

    environment = { TZ = tz; };

    ports = [ ];
    volumes = [ ];

    extraOptions = [ "--network=container:gluetun" ];
  };

  systemd.services.podman-flaresolverr = {
    after = [ "podman-gluetun.service" "podman.service" ];
    requires = [ "podman-gluetun.service" "podman.service" ];
  };
}
