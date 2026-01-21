{ lib, config, ... }:

let ips = config.homelab.ips;
in {
  options.homelab.network.staticIPv4 = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "If set, configures a static IPv4 address on ens18";
  };

  config = lib.mkIf (config.homelab.network.staticIPv4 != null) {
    systemd.network.networks."10-lan" = {
      matchConfig.Name = "ens18";
      networkConfig = {
        DHCP = "no";
        Address = [ "${config.homelab.network.staticIPv4}/24" ];
        Gateway = ips.router;
        DNS = [ ips.gw ];
      };
    };
  };
}
