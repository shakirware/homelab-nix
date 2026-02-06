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
    router = "192.168.1.1";
    gw = "192.168.1.2";
    proxmox = "192.168.1.100";
    storage = "192.168.1.110";
    media = "192.168.1.120";
    apps = "192.168.1.130";
    sensitive = "192.168.1.140";
    monitoring = "192.168.1.150";
  };
}
