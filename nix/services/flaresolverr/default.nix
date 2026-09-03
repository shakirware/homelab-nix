{ lib, ... }:

let tz = "Europe/London";
in {
  virtualisation.oci-containers.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:v3.5.0@sha256:139dfee1c6f89249c8d665d1333a42e8ec74ec0a86bc6bb1c8461e10d3a66a47";
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
