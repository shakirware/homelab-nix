{ pkgs, lib, ... }:

let
  mergerfsOptions = [
    "allow_other"
    "use_ino"
    "cache.files=partial"
    "dropcacheonclose=true"
    "category.create=ff"
    "moveonenospc=true"
    "minfreespace=50G"
    "nofail"
    "x-systemd.mount-timeout=60s"
  ];
in {
  environment.systemPackages = with pkgs; [ mergerfs fuse3 smartmontools ];

  programs.fuse.userAllowOther = true;

  systemd.tmpfiles.rules = [
    "d /srv/diskA 0755 root root - -"
    "d /srv/diskB 0755 root root - -"
    "d /srv/diskA/data 0755 root root - -"
    "d /srv/diskB/data 0755 root root - -"
    "d /srv/media 2775 shakir media - -"
  ];

  fileSystems."/srv/diskA" = {
    device = "/dev/disk/by-label/diskA";
    fsType = "ext4";
    options = [ "nofail" "noatime" "x-systemd.device-timeout=30" ];
  };

  fileSystems."/srv/diskB" = {
    device = "/dev/disk/by-label/diskB";
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

  services.nfs.server.enable = true;
  services.nfs.server.exports = ''
    /srv/media *(rw,fsid=0,no_subtree_check,async)
  '';

  systemd.services.nfs-server.unitConfig.RequiresMountsFor = [ "/srv/media" ];
  systemd.services.nfs-server.wants = [ "network-online.target" ];
  systemd.services.nfs-server.after = [ "network-online.target" ];

  networking.firewall.allowedTCPPorts = [ 2049 ];
  networking.firewall.allowedUDPPorts = [ 2049 ];

}
