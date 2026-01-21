{ lib, ... }:

let
  tz = "Europe/London";
  bindIp = "0.0.0.0";
in {
  virtualisation.oci-containers.containers.jellyseerr = {
    image = "ghcr.io/fallenbagel/jellyseerr:2.7.3";
    autoStart = true;

    environment = {
      TZ = tz;
      PORT = "5055";
    };

    volumes = [ "/srv/appdata/jellyseerr:/app/config" ];

    ports = [ "${bindIp}:5055:5055" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 5055 ];
}
