{ lib, ... }:

let
  tz = "Europe/London";
  bindIp = "0.0.0.0";
in {
  virtualisation.oci-containers.containers.seerr = {
    image = "ghcr.io/seerr-team/seerr:v3.5.0@sha256:27602401178d54f1964442287b9f23f67a3fa2252645ee8065839ea1c3f69e45";
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
