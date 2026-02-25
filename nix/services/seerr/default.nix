{ lib, ... }:

let
  tz = "Europe/London";
  bindIp = "0.0.0.0";
in {
  virtualisation.oci-containers.containers.seerr = {
    image = "ghcr.io/seerr-team/seerr:v3.0.1";
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
}
