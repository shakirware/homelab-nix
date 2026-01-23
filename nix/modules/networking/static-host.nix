{ lib, config, ... }:

let ips = config.homelab.ips;
in {
  options.homelab.network.staticIPv4 = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "If set, configures a static IPv4 address on primary NIC";
  };

  options.homelab.network.staticMac = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "MAC address of the NIC to configure (recommended).";
  };

  config = lib.mkIf (config.homelab.network.staticIPv4 != null
    && config.homelab.network.staticMac != null) {
      systemd.network.networks."10-lan" = {
        matchConfig.MACAddress = config.homelab.network.staticMac;
        networkConfig = {
          DHCP = "no";
          Address = [ "${config.homelab.network.staticIPv4}/24" ];
          Gateway = ips.router;
          DNS = [ ips.gw ];
        };
      };
    };
}
