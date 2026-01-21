{ lib, config, ... }:

let
  ips = config.homelab.ips or { };
  hasGw = ips ? gw;
in {
  systemd.network.enable = lib.mkDefault true;

  networking.useDHCP = lib.mkDefault false;

  services.resolved.enable = lib.mkDefault true;

  networking.firewall.enable = lib.mkDefault true;
  networking.nftables.enable = lib.mkDefault true;
  networking.firewall.allowPing = lib.mkDefault true;

  networking.nameservers =
    lib.mkDefault (if hasGw then [ ips.gw ] else [ "1.1.1.1" "9.9.9.9" ]);

  systemd.network.networks."10-lan" = lib.mkDefault {
    matchConfig.Name = "ens18";
    networkConfig = { DHCP = "yes"; };
  };
}
