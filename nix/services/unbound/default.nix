{ lib, ... }:

{
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
}
