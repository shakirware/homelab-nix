{ lib, config, pkgs, ... }:

let
  # Adjust labels if you change your disks
  diskA = "/dev/disk/by-label/diskA";
  diskB = "/dev/disk/by-label/diskB";

  mergerfsOptions = [
    "allow_other"
    "use_ino"
    "category.create=ff"
    "moveonenospc=true"
    "minfreespace=50G"
    "nofail"
    "x-systemd.mount-timeout=60s"
  ];

in {
  environment.systemPackages = with pkgs; [ mergerfs fuse3 ];

  programs.fuse.userAllowOther = true;

  systemd.tmpfiles.rules = lib.mkAfter [
    "d /srv/diskA 0755 root root - -"
    "d /srv/diskB 0755 root root - -"
    "d /srv/diskA/data 0755 root root - -"
    "d /srv/diskB/data 0755 root root - -"
    "d /srv/media 2775 ${config.homelab.ids.user} media - -"
  ];

  fileSystems."/srv/diskA" = {
    device = diskA;
    fsType = "ext4";
    options = [ "nofail" "noatime" "x-systemd.device-timeout=30" ];
  };

  fileSystems."/srv/diskB" = {
    device = diskB;
    fsType = "ext4";
    options = [ "nofail" "noatime" "x-systemd.device-timeout=30" ];
  };

  systemd.mounts = [{
    what = "/srv/diskA/data:/srv/diskB/data";
    where = "/srv/media";
    type = "fuse.mergerfs";
    options = lib.concatStringsSep "," (mergerfsOptions ++ [
      "rw"
      "x-systemd.requires-mounts-for=/srv/diskA"
      "x-systemd.requires-mounts-for=/srv/diskB"
    ]);

    wantedBy = [ "multi-user.target" ];
    after = [ "srv-diskA.mount" "srv-diskB.mount" "network-online.target" ];
    requires = [ "srv-diskA.mount" "srv-diskB.mount" ];
  }];

}
