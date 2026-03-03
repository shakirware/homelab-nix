{ config, lib, ... }:

{
  sops.secrets.TAILSCALE_AUTHKEY = { };

  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets.TAILSCALE_AUTHKEY.path;
    useRoutingFeatures = "server";
  };

  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  networking.firewall.allowedUDPPorts = [ 41641 ];

  systemd.services.tailscale-autoconnect = {
    description = "Auto-connect to Tailscale";
    after = [ "sops-nix.service" "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -euo pipefail

      ${lib.getExe config.services.tailscale.package} up \
        --authkey "file:${config.sops.secrets.TAILSCALE_AUTHKEY.path}" \
        --ssh \
        --accept-dns=false \
        --advertise-routes=192.168.20.0/24 \
        --advertise-exit-node
    '';
  };
}
