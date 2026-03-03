{ lib, ... }:

let tz = "Europe/London";
in {
  virtualisation.oci-containers.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:v3.4.6";
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
