{ lib, config, ... }:

let
  exports = ''
    /srv/media *(rw,fsid=0,no_subtree_check,async)
  '';
in {
  services.nfs.server.enable = true;
  services.nfs.server.exports = exports;

  systemd.services.nfs-server.unitConfig.RequiresMountsFor = [ "/srv/media" ];
  systemd.services.nfs-server.wants = [ "network-online.target" ];
  systemd.services.nfs-server.after = [ "network-online.target" ];

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 2049 ];
  networking.firewall.allowedUDPPorts = lib.mkAfter [ 2049 ];
}
