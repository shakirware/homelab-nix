{ lib, ... }:

{
  options.homelab.baseDomain = lib.mkOption {
    type = lib.types.str;
    default = "home.arpa";
    description = "Base DNS domain for the homelab";
  };

  options.homelab.domains = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "DNS records map: FQDN -> IP address";
  };

  options.homelab.webHosts = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        host = lib.mkOption {
          type = lib.types.str;
          description = "Hostname to serve ";
        };
        upstream = lib.mkOption {
          type = lib.types.str;
          description = "Upstream address";
        };
      };
    });
    default = [ ];
    description = "Reverse proxy hosts: host -> upstream address";
  };
}
