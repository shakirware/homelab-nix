{ config, lib, ... }:

{
  virtualisation.oci-containers.containers.seerr = {
    image = "ghcr.io/seerr-team/seerr:v3.5.2@sha256:aadee014b40e28cf9aa4928bc9d1183a6eb08f8c44d543cddc9efdcb16549be2";
    environment = {
      TZ = config.time.timeZone;
      PORT = "5055";
    };

    volumes = [ "/srv/appdata/seerr:/app/config" ];

    extraOptions = [ "--init" ];
  };

  homelab.containers.seerr.publish."5055" = [ config.homelab.ips.gw ];

  homelab.backup = {
    paths = [ "/srv/appdata/seerr" ];
    exclude = [
      "/srv/appdata/seerr/cache"
      "/srv/appdata/seerr/logs"
      "/srv/appdata/seerr/db"
    ];
    sqlite = [ "/srv/appdata/seerr/db/db.sqlite3" ];
  };
}
