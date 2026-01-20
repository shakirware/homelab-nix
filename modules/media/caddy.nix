{ config, lib, ... }:

let
  vhosts = builtins.listToAttrs (map (h: {
    name = h.host;
    value = {
      extraConfig = ''
        tls internal
        encode gzip zstd
        reverse_proxy ${h.upstream}
      '';
    };
  }) config.homelab.webHosts);
in {
  services.caddy = {
    enable = true;
    virtualHosts = vhosts;
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 80 443 ];
}
