{ lib, config, ... }:

let
  ips = config.homelab.ips;

  # The only hosts that mount the pool, and how. Anything else, including
  # every LAN and Wi-Fi device, is refused by both the export and the guard
  # below.
  clients = {
    ${ips.media} = "rw";
    ${ips.gw} = "ro"; # Homepage only reads disk usage
  };

  exportOptions = mode: "${mode},fsid=0,no_subtree_check,async";
  exports = ''
    /srv/media ${
      lib.concatStringsSep " "
      (lib.mapAttrsToList (ip: mode: "${ip}(${exportOptions mode})") clients)
    }
  '';
in {
  services.nfs.server.enable = true;
  services.nfs.server.exports = exports;

  # Apply export edits with `exportfs -r` (the unit's ExecReload) instead of
  # restarting nfsd, which would put every client through the NFSv4 grace
  # period and stall playback.
  systemd.services.nfs-server.restartTriggers = lib.mkForce [ ];
  systemd.services.nfs-server.reloadTriggers = [ exports ];

  systemd.services.nfs-server.unitConfig.RequiresMountsFor = [ "/srv/media" ];
  # Restarting the pool stops nfsd through the requirement above; this brings
  # it back when the pool is mounted again, instead of leaving exports down.
  systemd.services.nfs-server.wantedBy = [ "srv-media.mount" ];
  systemd.services.nfs-server.wants = [ "network-online.target" ];
  systemd.services.nfs-server.requires = [ "media-library-dirs.service" ];
  systemd.services.nfs-server.after =
    [ "network-online.target" "media-library-dirs.service" ];

  # NFSv4 is TCP only; port 2049 stays open in the NixOS firewall and the
  # guard narrows it to the client list.
  networking.firewall.allowedTCPPorts = lib.mkAfter [ 2049 ];

  networking.nftables.tables."nfs-client-guard" = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -50; policy accept;
        tcp dport 2049 jump nfs_guard
        udp dport 2049 jump nfs_guard
      }

      chain nfs_guard {
        ct state established,related accept
        iifname "lo" accept
        ip saddr { ${lib.concatStringsSep ", " (lib.attrNames clients)} } accept
        drop
      }
    '';
  };
}
