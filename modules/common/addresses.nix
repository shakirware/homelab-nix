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
    proxmox = "192.168.1.100";
    router = "192.168.1.254";
    media = "192.168.1.120";
    storage = "192.168.1.110";
  };
}
