{ config, lib, ... }:

let
  tz = "Europe/London";

  bindIp = "0.0.0.0";
  port = 11011;

  appdataDir = "/srv/appdata/cleanuparr";

  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  gwIp = config.homelab.ips.gw;
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${appdataDir} 2775 ${config.homelab.ids.user} media - -"
  ];

  virtualisation.oci-containers.containers.cleanuparr = {
    image = "ghcr.io/cleanuparr/cleanuparr:2.10.12@sha256:d0212e4c66bd0522e23c5e5da5d3006bd5ff0e0de1e3ecfcf892e039d55721e2";
    autoStart = true;

    environment = {
      TZ = tz;
      PORT = toString port;
      PUID = puid;
      PGID = pgid;
      UMASK = "022";
    };

    # /data is deliberate: qBittorrent sees /srv/downloads as /data in your stack.
    volumes = [
      "${appdataDir}:/config"
      "/srv/downloads:/data"
    ];

    ports = [ "${bindIp}:${toString port}:${toString port}" ];
  };

  systemd.services.podman-cleanuparr = {
    after = [ "podman.service" "network-online.target" ];
    requires = [ "podman.service" ];
    wants = [ "network-online.target" ];
  };

  # Reverse-proxy-only access from vm-gw
  # Hooked before dstnat: Podman DNATs the published port, so the packet is
  # forwarded to the container and never reaches the input hook.
  networking.nftables.tables."cleanuparr-backend-guard" = {
    family = "inet";
    content = ''
      chain prerouting {
        type filter hook prerouting priority -150; policy accept;
        fib daddr type local tcp dport ${toString port} jump cleanuparr_guard
      }

      chain cleanuparr_guard {
        ct state established,related accept
        iifname "lo" accept
        ip saddr ${gwIp} accept
        drop
      }
    '';
  };

  # events.db is an activity log and is left out.
  homelab.backup = {
    paths = [ appdataDir ];
    exclude = [ "${appdataDir}/logs" "${appdataDir}/*.db" ];
    sqlite = [ "${appdataDir}/cleanuparr.db" "${appdataDir}/users.db" ];
  };
}
