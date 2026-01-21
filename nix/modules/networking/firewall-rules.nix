{ lib, config, ... }:

let homeCidr = (config.home or { cidr = "192.168.1.0/24"; }).cidr;
in {
  options.homelab.firewall.adminCidr = lib.mkOption {
    type = lib.types.str;
    default = homeCidr;
    description = "CIDR allowed to access admin services";
  };

  options.homelab.firewall.allowAdminPorts = lib.mkOption {
    type = lib.types.listOf lib.types.port;
    default = [ ];
    description = "Ports that should only be reachable from adminCidr";
  };

  config = lib.mkIf (config.homelab.firewall.allowAdminPorts != [ ]) {
    networking.nftables.tables."homelab-admin" = {
      family = "inet";
      content = ''
        chain input {
          type filter hook input priority 0; policy accept;

          # allow established/related
          ct state established,related accept

          # allow loopback
          iifname "lo" accept

          # allow ICMP
          ip protocol icmp accept
          ip6 nexthdr icmpv6 accept

          # allow admin-only ports from admin subnet
          ip saddr ${config.homelab.firewall.adminCidr} tcp dport { ${
            lib.concatStringsSep ", "
            (map toString config.homelab.firewall.allowAdminPorts)
          } } accept

          # drop admin-only ports from everywhere else
          tcp dport { ${
            lib.concatStringsSep ", "
            (map toString config.homelab.firewall.allowAdminPorts)
          } } drop
        }
      '';
    };
  };
}
