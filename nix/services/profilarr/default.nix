{ config, lib, ... }:

let
  tz = "Europe/London";
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
  port = 6868;
in {
  virtualisation.oci-containers.containers.profilarr = {
    image = "santiagosayshey/profilarr:v1.1.5@sha256:8033e9c6d6995f37625afeb93d7020e99566f549ae83b65f1db7e11048952d0f";

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

  homelab.backup = {
    paths = [ "/srv/appdata/profilarr" ];
    exclude = [
      "/srv/appdata/profilarr/backups"
      "/srv/appdata/profilarr/log"
      "/srv/appdata/profilarr/profilarr.db"
    ];
    sqlite = [ "/srv/appdata/profilarr/profilarr.db" ];
  };
}
