{ config, ... }:
let ips = config.homelab.ips;
in {
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "ens18";
    networkConfig = {
      Address = [ "${ips.gw}/24" ];
      Gateway = ips.router;
      DNS = [ ips.gw ];
    };
  };
}
