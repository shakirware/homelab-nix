{ config, lib, ... }:

{
  virtualisation.oci-containers.containers.flaresolverr = {
    image = "ghcr.io/flaresolverr/flaresolverr:v3.5.2@sha256:c80ae007ce2ccdcd217a12426e4f039ef763ff90738c808d38810c3e59323767";
    environment = { TZ = config.time.timeZone; };
  };

  homelab.containers.flaresolverr = {
    vpn = true;
    memory = "2g";
  };
}
