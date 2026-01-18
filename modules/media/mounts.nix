{ config, ... }:

{
  fileSystems."/srv/media" = {
    device = "${config.homelab.ips.storage}:/";
    fsType = "nfs";
    options = [
      "nfsvers=4.2"
      "_netdev"
      "nofail"
      "noatime"
      "x-systemd.requires=network-online.target"
      "x-systemd.after=network-online.target"
      "x-systemd.mount-timeout=30s"
    ];
  };
}

