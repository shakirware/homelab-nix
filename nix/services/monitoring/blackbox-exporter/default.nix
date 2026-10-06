{ pkgs, ... }:

let
  port = 9115;

  # Probes go through Caddy on vm-gw, so they exercise DNS, TLS and the
  # reverse proxy as well as the upstream application.
  blackboxYaml = pkgs.writeText "blackbox.yml" ''
    modules:
      http_2xx:
        prober: http
        timeout: 14s
        http:
          preferred_ip_protocol: ip4
          ip_protocol_fallback: false
          follow_redirects: true
          fail_if_not_ssl: true

      # For services that deliberately require authentication on every path
      # (e.g. CouchDB): a 401 from the application still proves it is up.
      http_auth_required:
        prober: http
        timeout: 14s
        http:
          preferred_ip_protocol: ip4
          ip_protocol_fallback: false
          follow_redirects: true
          fail_if_not_ssl: true
          valid_status_codes: [ 200, 401 ]
  '';
in {
  services.prometheus.exporters.blackbox = {
    enable = true;
    inherit port;
    listenAddress = "127.0.0.1";
    configFile = blackboxYaml;
  };
}
