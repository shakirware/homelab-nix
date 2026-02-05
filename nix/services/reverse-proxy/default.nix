{ config, lib, pkgs, ... }:

let
  commonProxy = h: ''
        log {
          output stdout
          format console
          level INFO
        }

        request_body {
          max_size 1GB
        }

        tls {
          dns cloudflare {env.CLOUDFLARE_API_TOKEN}
          resolvers 1.1.1.1 1.0.0.1
        }

    ${lib.optionalString (h.corsAllowOrigin != null) ''
      @cors_origin header Origin ${h.corsAllowOrigin}

      @cors_preflight {
        method OPTIONS
        header Origin ${h.corsAllowOrigin}
      }

      handle @cors_preflight {
        header Access-Control-Allow-Origin "{http.request.header.Origin}"
        header Access-Control-Allow-Methods "GET, POST, PUT, PATCH, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "content-type, x-application-version, x-snjs-version, authorization"
        header Access-Control-Allow-Credentials "true"
        header Vary "Origin"
        respond "" 204
      }

      header @cors_origin {
        Access-Control-Allow-Origin "{http.request.header.Origin}"
        Access-Control-Allow-Credentials "true"
        Vary "Origin"
      }
    ''}

        encode gzip zstd

        reverse_proxy ${h.upstream} {
          header_up Host {host}
          header_up X-Real-IP {remote_host}
          header_up X-Forwarded-For {remote_host}
          header_up X-Forwarded-Proto {scheme}

          ${
            lib.optionalString (h.corsAllowOrigin != null) ''
              # Avoid duplicate CORS headers if the upstream also sets them.
              # Duplicates become "a, b" in the browser and fail CORS validation.
              header_down -Access-Control-Allow-Origin
              header_down -Access-Control-Allow-Credentials
              header_down -Access-Control-Allow-Methods
              header_down -Access-Control-Allow-Headers
              header_down -Access-Control-Expose-Headers
              header_down -Vary
            ''
          }

          ${
            lib.optionalString (h.upstreamTlsInsecure or false) ''
              transport http {
                tls_insecure_skip_verify
              }
            ''
          }
        }
  '';

  vhosts = builtins.listToAttrs (map (h: {
    name = h.host;
    value.extraConfig = commonProxy h;
  }) config.homelab.webHosts);

in {
  services.caddy = {
    enable = true;

    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.2" ];
      hash = "sha256-dnhEjopeA0UiI+XVYHYpsjcEI6Y1Hacbi28hVKYQURg=";
    };

    environmentFile = config.sops.templates."caddy-cloudflare".path;
    virtualHosts = vhosts;
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 80 443 ];
}
