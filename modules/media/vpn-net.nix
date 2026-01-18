{ pkgs, ... }:

let
  vpnNet = "vpn-net";
  podman = "${pkgs.podman}/bin/podman";
  bash = "${pkgs.bash}/bin/bash";
in {
  systemd.services."podman-network-${vpnNet}" = {
    description = "Ensure podman network ${vpnNet} exists";
    wantedBy = [ "multi-user.target" ];
    after = [ "podman.service" ];
    requires = [ "podman.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''
        ${bash} -lc "${podman} network inspect ${vpnNet} >/dev/null 2>&1 || ${podman} network create --subnet 10.99.0.0/24 --gateway 10.99.0.1 ${vpnNet}"
      '';
    };
  };
}
