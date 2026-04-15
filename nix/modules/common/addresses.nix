{ lib, ... }:

{
  options.homelab = {
    ips = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Homelab IP address map.";
    };
  };

  config.homelab.ips = {
    router_vlan1 = "192.168.1.1";
    router_vlan20 = "192.168.20.1";

    gw = "192.168.20.2";
    proxmox = "192.168.20.100";
    storage = "192.168.20.110";
    media = "192.168.20.120";
    apps = "192.168.20.130";
    sensitive = "192.168.20.140";
    monitoring = "192.168.20.150";
  };
}
