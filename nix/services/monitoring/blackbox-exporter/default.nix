{ config, pkgs, ... }:

let
  port = 9115;
  base = config.homelab.baseDomain;
  gwIp = config.homelab.ips.gw;

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

      # Router and WAN reachability.
      icmp:
        prober: icmp
        timeout: 5s
        icmp:
          preferred_ip_protocol: ip4
          ip_protocol_fallback: false

      # Resolution through AdGuard on vm-gw: an external name exercises the
      # Unbound upstream, an internal one the homelab rewrites.
      dns_external:
        prober: dns
        timeout: 5s
        dns:
          query_name: cloudflare.com
          query_type: A
          preferred_ip_protocol: ip4
          ip_protocol_fallback: false
          valid_rcodes: [ NOERROR ]
          validate_answer_rrs:
            fail_if_none_matches_regexp: [ '.*\tIN\tA\t.*' ]

      dns_internal:
        prober: dns
        timeout: 5s
        dns:
          query_name: grafana.${base}
          query_type: A
          preferred_ip_protocol: ip4
          ip_protocol_fallback: false
          valid_rcodes: [ NOERROR ]
          validate_answer_rrs:
            fail_if_none_matches_regexp: [ '.*\tIN\tA\t${builtins.replaceStrings [ "." ] [ "\\." ] gwIp}$' ]
  '';
in {
  services.prometheus.exporters.blackbox = {
    enable = true;
    inherit port;
    listenAddress = "127.0.0.1";
    configFile = blackboxYaml;
  };
}
