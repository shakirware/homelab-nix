{ lib, ... }:

let
  tz = "Europe/London";
  bindIp = "0.0.0.0";
in {
  virtualisation.oci-containers.containers.seerr = {
    image = "ghcr.io/seerr-team/seerr:v3.5.1@sha256:d8fab675b55ad293ded98fd71efcfd46054cbad9746534ae1cc4794a88c0b3be";
    autoStart = true;

    environment = {
      TZ = tz;
      PORT = "5055";
    };

    volumes = [ "/srv/appdata/seerr:/app/config" ];

    ports = [ "${bindIp}:5055:5055" ];

    extraOptions = [ "--init" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 5055 ];

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
