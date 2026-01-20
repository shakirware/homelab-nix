{ config, lib, ... }:

let
  rewrites = map (name: {
    domain = name;
    answer = config.homelab.domains.${name};
  }) (builtins.attrNames config.homelab.domains);
in {
  services.tailscale.enable = true;

  services.resolved.enable = false;

  networking.nameservers = [ "127.0.0.1" ];

  services.unbound = {
    enable = true;

    settings = {
      server = {
        interface = "127.0.0.1";
        port = 5335;

        do-ip6 = "no";
        do-udp = "yes";
        do-tcp = "yes";

        prefetch = "yes";
        cache-min-ttl = "60";
        cache-max-ttl = "86400";

        auto-trust-anchor-file = "/var/lib/unbound/root.key";

        access-control = [ "127.0.0.0/8 allow" ];
      };
    };
  };

  services.adguardhome = {
    enable = true;

    openFirewall = false;

    settings = {
      # Web UI
      http = { address = "0.0.0.0:3000"; };

      # DNS service
      dns = {
        bind_hosts = [ "0.0.0.0" ];
        port = 53;

        upstream_dns = [ "127.0.0.1:5335" ];

        bootstrap_dns = [ "1.1.1.1" "9.9.9.9" ];

        rewrites = rewrites;
      };

      filters = [
        {
          enabled = true;
          name = "AdGuard DNS filter";
          url =
            "https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt";
          id = 1;
        }
        {
          enabled = true;
          name = "OISD Basic";
          url = "https://big.oisd.nl/";
          id = 2;
        }
      ];
    };
  };

  networking.firewall.enable = true;

  # SSH + AdGuard UI + DNS
  networking.firewall.allowedTCPPorts = [ 22 3000 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
