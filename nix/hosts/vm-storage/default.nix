{ config, ... }:

let ips = config.homelab.ips;
in {
  imports = [ ../../profiles/base ../../profiles/storage ];

  systemd.network.networks."10-lan" = {
    matchConfig.Name = "ens18";
    networkConfig = {
      DHCP = "no";
      Address = [ "${ips.storage}/24" ];
      Gateway = ips.router;

      DNS = [ ips.gw ];
    };
  };
}
