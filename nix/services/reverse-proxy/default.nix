{ config, lib, ... }:

let
  commonProxy = upstream: ''
    log {
      output stdout
      format console
      level INFO
    }

    handle {
      encode gzip zstd
      reverse_proxy ${upstream} {
        header_up Host {host}
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
      }
    }
  '';

  vhosts = builtins.listToAttrs (map (h: {
    name = "${h.host}:80";
    value.extraConfig = commonProxy h.upstream;
  }) config.homelab.webHosts);
in {
  services.caddy = {
    enable = true;
    globalConfig = "auto_https off";
    virtualHosts = vhosts;
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 80 ];
}
