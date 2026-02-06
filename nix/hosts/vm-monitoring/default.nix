{ config, ... }:

let ips = config.homelab.ips;
in {
  imports = [ ../../profiles/base ../../profiles/monitoring ];

  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:9a:3f:06";
    networkConfig = {
      DHCP = "no";
      Address = [ "${ips.monitoring}/24" ];
      Gateway = ips.router;
      DNS = [ ips.gw ];
    };
  };

  sops = {
    defaultSopsFile = ../../../secrets/vm-monitoring.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  homelab.secrets.envTemplates."proxmox-exporter" = {
    env = {
      PVE_TOKEN_NAME = "proxmox/token_name";
      PVE_TOKEN_VALUE = "proxmox/token_value";
      PVE_USER = "proxmox/user";
    };
  };
}
