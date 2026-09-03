{ config, lib, ... }:

let
  baseDomain = config.homelab.baseDomain;
  localRecords = config.homelab.domains;
in {
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

        # Git owns local split-horizon records.  The transparent zone preserves
        # normal recursive resolution for public names below the same domain.
        local-zone = [ ''"${baseDomain}." transparent'' ];
        local-data = lib.mapAttrsToList
          (domain: address: ''"${domain}. 60 IN A ${address}"'') localRecords;

        access-control = [ "127.0.0.0/8 allow" ];
      };
    };
  };
}
