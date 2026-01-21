{ config, lib, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
  port = 6868;
in {
  virtualisation.oci-containers.containers.profilarr = {
    image = "santiagosayshey/profilarr:latest";

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
