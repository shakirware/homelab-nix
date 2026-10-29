{ config, lib, pkgs, ... }:

let
  tz = "Europe/London";

  port = 5173;
  bindIp = "0.0.0.0";

  net = "kaneo-net";

  subnet = "10.92.0.0/24";
  gateway = "10.92.0.1";
  dbIp = "10.92.0.2";
  appIp = "10.92.0.3";

  pgVol = "kaneo_pg_data";

  podman = "${pkgs.podman}/bin/podman";
  bash = "${pkgs.bash}/bin/bash";

  seq = "${pkgs.coreutils}/bin/seq";
  sleep = "${pkgs.coreutils}/bin/sleep";

  waitDb = pkgs.writeShellScript "kaneo-wait-db" ''
    set -euo pipefail

    echo "kaneo: waiting for PostgreSQL..."

    for i in $(${seq} 1 30); do
      if ${podman} exec kaneo-db \
        pg_isready -U kaneo -d kaneo -t 1 >/dev/null 2>&1; then
        exit 0
      fi

      ${sleep} 1
    done

    echo "kaneo: PostgreSQL did not become ready" >&2
    exit 1
  '';

  gwIp = config.homelab.ips.gw;

  envName = "kaneo.env";
  dbEnvName = "kaneo-db.env";
in {
  sops.secrets."kaneo/db_password" = { };
  sops.secrets."kaneo/auth_secret" = { };
  sops.secrets."kaneo/notification_key" = { };

  sops.templates.${envName} = {
    content = ''
      TZ=${tz}

      KANEO_CLIENT_URL=https://kaneo.${config.homelab.baseDomain}

      DATABASE_URL=postgres://kaneo:${
        config.sops.placeholder."kaneo/db_password"
      }@${dbIp}:5432/kaneo

      # Keep stable: rotating either logs everyone out or orphans saved tokens.
      AUTH_SECRET=${config.sops.placeholder."kaneo/auth_secret"}
      NOTIFICATION_SECRET_ENCRYPTION_KEY=${
        config.sops.placeholder."kaneo/notification_key"
      }

      # Re-enable briefly to add another account.
      DISABLE_REGISTRATION=true
    '';
    owner = "root";
    group = "root";
    mode = "0400";
    # This template includes the database password.  Rotation is a coordinated
    # PostgreSQL migration and must never trigger an ordinary restart.
    restartUnits = [ ];
  };

  sops.templates.${dbEnvName} = {
    content = ''
      POSTGRES_PASSWORD=${config.sops.placeholder."kaneo/db_password"}
    '';
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ ];
  };

  systemd.services."podman-network-${net}" = {
    description = "Ensure podman network ${net} exists";
    wantedBy = [ "multi-user.target" ];
    after = [ "podman.service" ];
    requires = [ "podman.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''
        ${bash} -lc "${podman} network inspect ${net} >/dev/null 2>&1 || ${podman} network create --subnet ${subnet} --gateway ${gateway} ${net}"
      '';
    };
  };

  virtualisation.oci-containers.containers = {
    kaneo-db = {
      image = "postgres:16-alpine@sha256:0cefaabd882e42bcb2a2f3dc56d3ce4770560ba62fd7f197f1a2e008fd5731ab";
      autoStart = true;

      environment = {
        POSTGRES_USER = "kaneo";
        POSTGRES_DB = "kaneo";
      };

      environmentFiles = [ config.sops.templates.${dbEnvName}.path ];

      volumes = [ "${pgVol}:/var/lib/postgresql/data" ];

      extraOptions = [ "--network=${net}" "--ip=${dbIp}" "--name=kaneo-db" ];
    };

    kaneo = {
      image = "ghcr.io/usekaneo/kaneo:2.48.0@sha256:e52b4d48bb5efd5cd9a113ce47ed49ea1fb9e9c1517fd73ea4dc1c7037666def";
      autoStart = true;

      environmentFiles = [ config.sops.templates.${envName}.path ];

      ports = [ "${bindIp}:${toString port}:5173" ];

      extraOptions = [ "--network=${net}" "--ip=${appIp}" "--name=kaneo" ];
    };
  };

  systemd.services.podman-kaneo-db = {
    after = [ "podman-network-${net}.service" "podman.service" ];
    requires = [ "podman-network-${net}.service" "podman.service" ];
  };

  systemd.services.podman-kaneo = {
    after = [
      "podman-network-${net}.service"
      "podman-kaneo-db.service"
      "podman.service"
    ];
    requires = [
      "podman-network-${net}.service"
      "podman-kaneo-db.service"
      "podman.service"
    ];

    serviceConfig.ExecStartPre = lib.mkAfter [ waitDb ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  # aardvark-dns on the gateway answers the containers' DNS.  Matched by
  # subnet: podmanN numbering isn't stable.
  networking.firewall.extraInputRules = lib.mkAfter ''
    ip saddr ${subnet} ip daddr ${gateway} meta l4proto { tcp, udp } th dport 53 accept
  '';

  # Only the gateway/reverse proxy may access Kaneo directly.  Hooked before
  # dstnat: netavark DNATs the published port, so the packet is forwarded to
  # the container and never reaches the input hook.
  networking.nftables.tables."kaneo-backend-guard" = {
    family = "inet";

    content = ''
      chain prerouting {
        type filter hook prerouting priority -150; policy accept;
        tcp dport ${toString port} jump kaneo_guard
      }

      chain kaneo_guard {
        ct state established,related accept
        iifname "lo" accept
        ip saddr ${gwIp} accept
        drop
      }
    '';
  };
}
