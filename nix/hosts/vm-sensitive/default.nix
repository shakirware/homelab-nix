{ config, ... }:

let ips = config.homelab.ips;
in {
  imports = [ ../../profiles/base ../../profiles/sensitive ];

  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:6d:92:b4";
    networkConfig = {
      DHCP = "no";
      Address = [ "${ips.sensitive}/24" ];
      Gateway = ips.router;
      DNS = [ ips.gw ];
    };
  };
}
