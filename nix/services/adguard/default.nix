{ lib, ... }:

{
  services.resolved.enable = lib.mkForce false;

  networking.nameservers = lib.mkForce [ "127.0.0.1" ];

  services.adguardhome = {
    enable = true;
    # Keep filters, users, query history and legitimate UI state mutable. Local
    # DNS records are authoritative in the upstream Unbound configuration.
    mutableSettings = true;

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
      };

      # AdGuard consults its own rewrites *before* the upstream resolver, so any
      # row left here would shadow the authoritative Unbound local-data.  This
      # list is declared empty so that every restart clears rewrites out of the
      # mutable state file, keeping local homelab records owned solely by Git
      # via Unbound.  yaml-merge recurses into `filtering`, so the remaining
      # mutable filtering state (filters, safe search, query log) is preserved.
      filtering = { rewrites = [ ]; };

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
