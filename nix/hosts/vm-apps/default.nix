{ config, ... }:
let ips = config.homelab.ips;
in {
  imports = [ ../../profiles/base ../../profiles/apps ];

  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:ad:85:c4";
    networkConfig = {
      DHCP = "no";
      Address = [ "${ips.apps}/24" ];
      Gateway = ips.router;
      DNS = [ ips.gw ];
    };
  };

  sops = {
    defaultSopsFile = ../../../secrets/vm-apps.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
