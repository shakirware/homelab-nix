{ pkgs, ... }:

let
  jellystatNet = "jellystat-net";
  podman = "${pkgs.podman}/bin/podman";
  bash = "${pkgs.bash}/bin/bash";
in {
  systemd.services."podman-network-${jellystatNet}" = {
    description = "Ensure podman network ${jellystatNet} exists";
    wantedBy = [ "multi-user.target" ];
    after = [ "podman.service" ];
    requires = [ "podman.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''
        ${bash} -lc "${podman} network inspect ${jellystatNet} >/dev/null 2>&1 || ${podman} network create --subnet 10.90.0.0/24 --gateway 10.90.0.1 ${jellystatNet}"
      '';
    };
  };

  systemd.services.podman-jellystat-db = {
    after = [ "podman-network-${jellystatNet}.service" "podman.service" ];
    requires = [ "podman-network-${jellystatNet}.service" "podman.service" ];
  };

  systemd.services.podman-jellystat = {
    after = [
      "podman-network-${jellystatNet}.service"
      "podman-jellystat-db.service"
      "podman.service"
    ];
    requires = [
      "podman-network-${jellystatNet}.service"
      "podman-jellystat-db.service"
      "podman.service"
    ];

    serviceConfig.ExecStartPre = [''
      ${bash} -lc "${podman} exec jellystat-db pg_isready -U postgres -t 5 || true"
    ''];
  };
}
