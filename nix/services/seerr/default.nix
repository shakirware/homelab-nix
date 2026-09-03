{ lib, ... }:

let
  tz = "Europe/London";
  bindIp = "0.0.0.0";
in {
  virtualisation.oci-containers.containers.seerr = {
    image = "ghcr.io/seerr-team/seerr:v3.4.0@sha256:d206d9e4056bb90178297df58047791196e7721e6dc19384579b0530702fe086";
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
