{ config, lib, ... }:

let
  tz = "Europe/London";

  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  port = 8901;

  baseDomain = config.homelab.baseDomain;
  host = "iptv.${baseDomain}";

  appdataDir = "/srv/appdata/iptv-proxy";

  gwIp = config.homelab.ips.gw;
in {
  systemd.tmpfiles.rules =
    lib.mkAfter [ "d ${appdataDir} 2775 ${config.homelab.ids.user} media - -" ];

  virtualisation.oci-containers.containers.iptv-proxy = {
    image = "sonroyaalmerol/m3u-stream-merger-proxy:latest";
    autoStart = true;

    ports = [ ];

    extraOptions = [ "--network=container:gluetun" ];

    environment = {
      TZ = tz;
      PUID = puid;
      PGID = pgid;

      PORT = toString port;
      BASE_URL = "https://${host}";

      SYNC_ON_BOOT = "true";
      SYNC_CRON = "*/30 * * * *";

      USER_AGENT =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122 Safari/537.36";
      INCLUDE_GROUPS_1 =
        "(?i)^U\\.K\\. - (SKY SPORTS\\+?|SKY SPORTS|TNT SPORT|DAZN|VIAPLAY|LIVE FOOTBALL|CHAMPIONSHIP/L1/L2/FACUP|EPL|SPORTS \\(OTHERS\\)).*$";
      MAX_RETRIES = "20";
      RETRY_WAIT = "10";
      STREAM_TIMEOUT = "15";
      M3U_MAX_CONCURRENCY_1 = "1";
      CLEAR_ON_BOOT = "true";
    };

    environmentFiles = lib.optionals (config.sops.templates ? "iptv-proxy")
      [ config.sops.templates."iptv-proxy".path ];

    volumes = [ "${appdataDir}:/m3u-proxy/data" ];
  };

  systemd.services.podman-iptv-proxy = {
    after = [ "podman-gluetun.service" "podman.service" ];
    requires = [ "podman-gluetun.service" "podman.service" ];
  };

  networking.nftables.tables."iptv-backend-guard" = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -50; policy accept;
        tcp dport ${toString port} jump iptv_guard
      }

      chain iptv_guard {
        ct state established,related accept
        iifname "lo" accept
        ip saddr ${gwIp} accept
        drop
      }
    '';
  };
}
