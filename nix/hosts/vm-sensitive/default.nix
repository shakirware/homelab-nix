{ config, lib, ... }:

let
  ips = config.homelab.ips;
  hasSensitiveIp = ips ? sensitive;
in {
  imports = [ ../../profiles/base ];

  systemd.network.networks."10-lan" = {
    matchConfig.Name = "ens18";

    networkConfig = if hasSensitiveIp then {
      DHCP = "no";
      Address = [ "${ips.sensitive}/24" ];
      Gateway = ips.router;
      DNS = [ ips.gw ];
    } else {
      DHCP = "yes";
    };
  };
}
