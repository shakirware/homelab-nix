{ config, ... }:

let ips = config.homelab.ips;
in {
  imports = [ ../../profiles/base ../../profiles/sensitive ];

  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:6d:92:b4";
    networkConfig = {
      DHCP = "no";
      Address = [ "${ips.sensitive}/24" ];
      Gateway = ips.router_vlan20;
      DNS = [ ips.gw ];
    };
  };

  sops = {
    defaultSopsFile = ../../../secrets/vm-sensitive.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
