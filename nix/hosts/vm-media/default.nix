{ config, ... }:

let ips = config.homelab.ips;
in {
  imports = [ ../../profiles/base ../../profiles/media ];

  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:bb:ac:8b";
    networkConfig = {
      DHCP = "no";
      Address = [ "${ips.media}/24" ];
      Gateway = ips.router_vlan20;
      DNS = [ ips.gw ];
    };
  };

  sops = {
    defaultSopsFile = ../../../secrets/vm-media.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  homelab.secrets.envTemplates."iptv-proxy" = {
    env = { M3U_URL_1 = "iptv/m3u_url_1"; };
  };
}
