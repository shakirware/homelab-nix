{ config, lib, pkgs, ... }:

let
  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
  hostPort = 6869;

  appdataDir = "/srv/appdata/profilarr-v2";

  net = "profilarr-v2-net";
  subnet = "10.94.0.0/24";
  gateway = "10.94.0.1";
  appIp = "10.94.0.2";
  parserIp = "10.94.0.3";

  podman = "${pkgs.podman}/bin/podman";
  bash = "${pkgs.bash}/bin/bash";
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${appdataDir} 2775 ${config.homelab.ids.user} media - -"
  ];

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
    profilarr-v2-parser = {
      image = "ghcr.io/dictionarry-hub/profilarr-parser:2.3.1@sha256:234084df7037e76b98c66f5ab220dc0d10ef8f34145ded57b9af257f057bdda6";
      extraOptions = [ "--network=${net}" "--ip=${parserIp}" "--name=profilarr-v2-parser" ];
    };

    profilarr-v2 = {
      image = "ghcr.io/dictionarry-hub/profilarr:2.3.1@sha256:352e42dec74ecfd68d13bb198fbc6d9346e3a8c55003026e1814e59319a2176d";
      environment = {
        TZ = config.time.timeZone;
        PUID = puid;
        PGID = pgid;
        PARSER_HOST = parserIp;
        PARSER_PORT = "5000";
        ORIGIN = "https://profilarr.${config.homelab.baseDomain}";
      };

      volumes = [ "${appdataDir}:/config" ];

      ports = [ "${bindIp}:${toString hostPort}:6868" ];

      extraOptions = [ "--network=${net}" "--ip=${appIp}" "--name=profilarr-v2" ];
    };
  };

  systemd.services.podman-profilarr-v2-parser = {
    after = [ "podman-network-${net}.service" "podman.service" ];
    requires = [ "podman-network-${net}.service" "podman.service" ];
  };

  systemd.services.podman-profilarr-v2 = {
    after = [
      "podman-network-${net}.service"
      "podman-profilarr-v2-parser.service"
      "podman.service"
    ];
    requires = [ "podman-network-${net}.service" "podman.service" ];
    wants = [ "podman-profilarr-v2-parser.service" ];
  };

  homelab.firewall.restrict.${toString hostPort} = [ config.homelab.ips.gw ];

  networking.firewall.extraInputRules = lib.mkAfter ''
    ip saddr ${subnet} ip daddr ${gateway} meta l4proto { tcp, udp } th dport 53 accept
  '';

  homelab.backup = {
    paths = [ appdataDir ];
    exclude = [
      "${appdataDir}/backups"
      "${appdataDir}/logs"
      "${appdataDir}/data/profilarr.db"
    ];
    sqlite = [ "${appdataDir}/data/profilarr.db" ];
  };
}
