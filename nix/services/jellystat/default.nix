{ config, lib, pkgs, ... }:

let
  tz = "Europe/London";
  bindIp = "0.0.0.0";

  jellystatNet = "jellystat-net";
  dbIp = "10.90.0.2";
  appIp = "10.90.0.3";

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

  virtualisation.oci-containers.containers.jellystat-db = {
    image = "postgres:15.2";
    autoStart = true;

    environment = {
      POSTGRES_USER = "postgres";
      POSTGRES_DB = "jellystat";
    };

    environmentFiles = [ config.sops.templates."jellystat-db.env".path ];

    volumes =
      [ "/srv/appdata/jellystat/postgres-data:/var/lib/postgresql/data" ];

    extraOptions =
      [ "--network=${jellystatNet}" "--ip=${dbIp}" "--name=jellystat-db" ];
  };

  virtualisation.oci-containers.containers.jellystat = {
    image = "cyfershepard/jellystat:1.1.7";
    autoStart = true;

    environment = {
      POSTGRES_USER = "postgres";
      POSTGRES_IP = dbIp;
      POSTGRES_PORT = "5432";
      TZ = tz;
    };

    environmentFiles = [ config.sops.templates."jellystat.env".path ];

    volumes = [ "/srv/appdata/jellystat:/app/backend/backup-data" ];

    ports = [ "${bindIp}:4001:3000" ];

    extraOptions =
      [ "--network=${jellystatNet}" "--ip=${appIp}" "--name=jellystat" ];
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

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 4001 ];
}
