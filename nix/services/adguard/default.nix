{ lib, config, ... }:

let rewrites = config.homelab.adguard.rewrites or [ ];
in {
  services.resolved.enable = lib.mkForce false;

  networking.nameservers = lib.mkForce [ "127.0.0.1" ];

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

        # Unbound local resolver
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

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 53 3000 ];
  networking.firewall.allowedUDPPorts = lib.mkAfter [ 53 ];
}
