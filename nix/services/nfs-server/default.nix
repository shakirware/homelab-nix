{ lib, config, pkgs, ... }:

let
  ips = config.homelab.ips;
  ids = config.homelab.ids;

  exportRoot = "/export";
  photosDir = "/srv/diskA/photos";

  # The only hosts that mount the pool, and how. Anything else, including
  # every LAN and Wi-Fi device, is refused by both the export and the guard
  # below.
  clients = [ ips.media ips.gw ips.apps ];

  exports = ''
    ${exportRoot} ${
      lib.concatMapStringsSep " " (ip: "${ip}(ro,fsid=0,no_subtree_check)")
      clients
    }
    ${exportRoot}/media ${ips.media}(rw,fsid=1,no_subtree_check,async) ${ips.gw}(ro,fsid=1,no_subtree_check,async)
    ${exportRoot}/photos ${ips.apps}(rw,fsid=2,no_subtree_check,sync,all_squash,anonuid=${
      toString ids.uid
    },anongid=${toString ids.mediaGid})
  '';
in {
  services.nfs.server.enable = true;
  services.nfs.server.exports = exports;

  # Apply export edits with `exportfs -r` (the unit's ExecReload) instead of
  # restarting nfsd, which would put every client through the NFSv4 grace
  # period and stall playback.
  systemd.services.nfs-server.restartTriggers = lib.mkForce [ ];
  systemd.services.nfs-server.reloadTriggers = [ exports ];

  systemd.services.nfs-server.unitConfig.RequiresMountsFor =
    [ "${exportRoot}/media" "${exportRoot}/photos" ];
  # Restarting the pool stops nfsd through the requirement above; this brings
  # it back when the pool is mounted again, instead of leaving exports down.
  systemd.services.nfs-server.wantedBy =
    [ "srv-media.mount" "export-media.mount" "export-photos.mount" ];
  systemd.services.nfs-server.wants = [ "network-online.target" ];
  systemd.services.nfs-server.requires = [ "media-library-dirs.service" ];
  systemd.services.nfs-server.after =
    [ "network-online.target" "media-library-dirs.service" ];

  systemd.services.nfs-export-dirs = {
    description = "Create the NFSv4 root and its mount points";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      install -d -m 0755 ${exportRoot}
      for d in ${exportRoot}/media ${exportRoot}/photos; do
        [ -e "$d" ] || install -d -m 0000 "$d"
      done
    '';
  };

  systemd.services.photos-dir = {
    description = "Create the Immich photo directory on diskA";
    unitConfig.RequiresMountsFor = [ "/srv/diskA" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      [ -d ${photosDir} ] || install -d -m 2775 -o ${toString ids.uid} -g ${toString ids.mediaGid} ${photosDir}
    '';
  };

  systemd.mounts = [
    {
      what = "/srv/media";
      where = "${exportRoot}/media";
      type = "none";
      options = "bind,nofail";
      bindsTo = [ "srv-media.mount" ];
      requires = [ "nfs-export-dirs.service" ];
      after = [ "srv-media.mount" "nfs-export-dirs.service" ];
      wantedBy = [ "srv-media.mount" ];
    }
    {
      what = photosDir;
      where = "${exportRoot}/photos";
      type = "none";
      options = "bind,nofail";
      requires = [ "srv-diskA.mount" "photos-dir.service" "nfs-export-dirs.service" ];
      after = [ "srv-diskA.mount" "photos-dir.service" "nfs-export-dirs.service" ];
      wantedBy = [ "multi-user.target" ];
    }
  ];

  # NFSv4 is TCP only; port 2049 stays open in the NixOS firewall and the
  # guard narrows it to the client list.
  networking.firewall.allowedTCPPorts = lib.mkAfter [ 2049 ];

  homelab.firewall.restrict = {
    "2049" = clients;
    "2049/udp" = clients;
  };
}
