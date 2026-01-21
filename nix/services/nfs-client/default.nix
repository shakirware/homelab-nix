{ lib, config, pkgs, ... }:

let
  server = config.homelab.ips.storage;

  export = "/";

  mountPoint = "/srv/media";
in {
  environment.systemPackages = [ pkgs.nfs-utils ];

  systemd.tmpfiles.rules =
    lib.mkAfter [ "d ${mountPoint} 2775 ${config.homelab.ids.user} media - -" ];

  fileSystems.${mountPoint} = {
    device = "${server}:${export}";
    fsType = "nfs4";

    options = [
      "nofail"
      "noatime"
      "_netdev"
      "x-systemd.mount-timeout=60s"
      "x-systemd.requires=network-online.target"
      "x-systemd.after=network-online.target"
    ];
  };
}
