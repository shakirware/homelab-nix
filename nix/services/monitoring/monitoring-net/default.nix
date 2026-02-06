{ pkgs, ... }:

let
  net = "monitoring-net";
  podman = "${pkgs.podman}/bin/podman";
  bash = "${pkgs.bash}/bin/bash";
in {
  systemd.services."podman-network-${net}" = {
    description = "Ensure podman network ${net} exists";
    wantedBy = [ "multi-user.target" ];
    after = [ "podman.service" ];
    requires = [ "podman.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''
        ${bash} -lc "${podman} network inspect ${net} >/dev/null 2>&1 || ${podman} network create ${net}"
      '';
    };
  };
}
