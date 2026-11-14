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
          description = "Hostname to serve";
        };
        upstream = lib.mkOption {
          type = lib.types.str;
          description = "Upstream address";
        };
        corsAllowOrigin = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description =
            "If set, Caddy will handle CORS + OPTIONS preflight for this vhost.";
        };
        maxBodySize = lib.mkOption {
          type = lib.types.str;
          default = "1GB";
          description = "Largest request body Caddy accepts for this vhost.";
        };
        upstreamTlsInsecure = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description =
            "Skip TLS verification when proxying to an HTTPS upstream.";
        };
        probePath = lib.mkOption {
          type = lib.types.str;
          default = "/";
          description = ''
            Unauthenticated health endpoint that Blackbox probes over HTTPS.
            Every vhost is probed, so new services are covered by default.
          '';
        };
        probeModule = lib.mkOption {
          type = lib.types.enum [ "http_2xx" "http_auth_required" ];
          default = "http_2xx";
          description = ''
            Blackbox module for the probe; `http_auth_required` accepts a 401
            from services that require auth on every path.
          '';
        };
      };
    });
    default = [ ];
    description = "Reverse proxy hosts: host -> upstream address";
  };
}
