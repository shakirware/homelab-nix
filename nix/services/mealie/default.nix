{ config, lib, ... }:

let
  tz = "Europe/London";

  bindIp = "0.0.0.0";
  port = 9000;

  dataDir = "/srv/appdata/mealie";

  uid = toString config.homelab.ids.uid;
  gid = toString config.homelab.ids.mediaGid;

  gwIp = config.homelab.ips.gw;
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${dataDir} 2775 ${config.homelab.ids.user} media - -"
  ];

  virtualisation.oci-containers.containers.mealie = {
    image = "ghcr.io/mealie-recipes/mealie:v3.30.0@sha256:90f83da6f3ab0a421efc827118a556168573930105f13fa3321768f42163d784";
    autoStart = true;

    environment = {
      TZ = tz;

      PUID = uid;
      PGID = gid;

      BASE_URL = "https://mealie.${config.homelab.baseDomain}";
      ALLOW_SIGNUP = "false";
      DB_ENGINE = "sqlite";
    };

    volumes = [
      "${dataDir}:/app/data"
    ];

    ports = [
      "${bindIp}:${toString port}:9000"
    ];

    extraOptions = [
      "--memory=1g"
    ];
  };

  systemd.services.podman-mealie = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  networking.nftables.tables."mealie-backend-guard" = {
    family = "inet";

    content = ''
      chain prerouting {
        type filter hook prerouting priority -150; policy accept;
        fib daddr type local tcp dport ${toString port} jump mealie_guard
      }

      chain mealie_guard {
        ct state established,related accept
        iifname "lo" accept
        ip saddr ${gwIp} accept
        drop
      }
    '';
  };

  homelab.backup = {
    paths = [ dataDir ];
    exclude = [
      "${dataDir}/mealie.db"
      "${dataDir}/mealie.db-*"
    ];
    sqlite = [ "${dataDir}/mealie.db" ];
  };
}
