{ config, ... }:

let ips = config.homelab.ips;
in {
  imports = [ ../../profiles/base ../../profiles/storage ];

  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:ec:74:e6";
    networkConfig = {
      DHCP = "no";
      Address = [ "${ips.storage}/24" ];
      Gateway = ips.router_vlan20;
      DNS = [ ips.gw ];
    };
  };

  sops = {
    defaultSopsFile = ../../../secrets/vm-storage.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
