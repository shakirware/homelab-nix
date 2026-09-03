{ config, lib, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
  port = 6868;
in {
  virtualisation.oci-containers.containers.profilarr = {
    image = "santiagosayshey/profilarr:latest@sha256:c8ad91a8e5d60b3816321b3a1f68332b29a23f910f6bd2c2d7b4a83f881f032f";

    autoStart = true;

    environment = {
      TZ = tz;
      PUID = puid;
      PGID = pgid;
    };

    volumes = [ "/srv/appdata/profilarr:/config" ];

    ports = [ "${bindIp}:${toString port}:${toString port}" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];
}
