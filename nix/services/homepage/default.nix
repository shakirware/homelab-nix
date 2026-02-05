{ config, lib, pkgs, ... }:

let
  tz = "Europe/London";
  cfgDir = "/srv/appdata/homepage";

  listenHost = "127.0.0.1";
  listenPort = 3001;

  puid = toString config.homelab.ids.uid;
  pgid = toString config.homelab.ids.mediaGid;

  ips = config.homelab.ips;
  baseDomain = config.homelab.baseDomain;

  gwIp = ips.gw;
  mediaIp = ips.media;
  appsIp = ips.apps;
  proxmoxIp = ips.proxmox;
  routerIp = ips.router;

  homepageHost = "homepage.${baseDomain}";
  adguardHost = "adguard.${baseDomain}";
  jellyfinHost = "jellyfin.${baseDomain}";
  jellyseerrHost = "jellyseerr.${baseDomain}";
  jellystatHost = "jellystat.${baseDomain}";
  sonarrHost = "sonarr.${baseDomain}";
  radarrHost = "radarr.${baseDomain}";
  prowlarrHost = "prowlarr.${baseDomain}";
  qbittorrentHost = "qbittorrent.${baseDomain}";
  iptvHost = "iptv.${baseDomain}";
  uptimeHost = "uptime.${baseDomain}";
  profilarrHost = "profilarr.${baseDomain}";

  proxmoxHost = "proxmox.${baseDomain}";
  routerHost = "router.${baseDomain}";
  storageHost = "storage.${baseDomain}";
  mediaHost = "media.${baseDomain}";
  obsidianSyncHost = "obsidian-sync.${baseDomain}";
  actualHost = "actual.${baseDomain}";
  standardnotesHost = "notes.${baseDomain}";

  settingsYaml = ./config/settings.yaml;
  widgetsTpl = ./config/widgets.yaml.in;
  servicesTpl = ./config/services.yaml.in;

  vars = {
    GW_IP = gwIp;
    MEDIA_IP = mediaIp;
    APPS_IP = appsIp;
    PROXMOX_IP = proxmoxIp;
    ROUTER_IP = routerIp;

    BASE_DOMAIN = baseDomain;

    HOMEPAGE_HOST = homepageHost;
    ADGUARD_HOST = adguardHost;
    UPTIME_HOST = uptimeHost;

    JELLYFIN_HOST = jellyfinHost;
    JELLYSEERR_HOST = jellyseerrHost;
    JELLYSTAT_HOST = jellystatHost;

    SONARR_HOST = sonarrHost;
    RADARR_HOST = radarrHost;
    PROWLARR_HOST = prowlarrHost;
    QBITTORRENT_HOST = qbittorrentHost;
    IPTV_HOST = iptvHost;
    PROFILARR_HOST = profilarrHost;

    PROXMOX_HOST = proxmoxHost;
    ROUTER_HOST = routerHost;
    STORAGE_HOST = storageHost;
    MEDIA_HOST = mediaHost;

    OBSIDIAN_SYNC_HOST = obsidianSyncHost;

    ACTUAL_HOST = actualHost;
    STANDARDNOTES_HOST = standardnotesHost;
  };

  keys = builtins.attrNames vars;
  placeholders = map (k: "@${k}@") keys;
  values = map (k: vars.${k}) keys;

  render = src: outName:
    pkgs.writeText outName
    (lib.replaceStrings placeholders values (builtins.readFile src));

  widgetsRendered = render widgetsTpl "widgets.yaml";
  servicesRendered = render servicesTpl "services.yaml";
in {
  systemd.tmpfiles.rules =
    [ "d ${cfgDir} 2775 ${config.homelab.ids.user} media - -" ];

  systemd.services.homepage-config = {
    description = "Sync Homepage YAML config from repo";
    wantedBy = [ "multi-user.target" ];
    before = [ "podman-homepage.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = [ pkgs.coreutils ];

    script = ''
      set -euo pipefail

      install -d -m 2775 -o ${config.homelab.ids.user} -g media ${cfgDir}

      # settings.yaml has no placeholders
      install -m 0664 -o ${puid} -g ${pgid} ${settingsYaml} ${cfgDir}/settings.yaml

      # rendered templates
      install -m 0664 -o ${puid} -g ${pgid} ${widgetsRendered}  ${cfgDir}/widgets.yaml
      install -m 0664 -o ${puid} -g ${pgid} ${servicesRendered} ${cfgDir}/services.yaml
    '';
  };

  virtualisation.oci-containers.containers.homepage = {
    image = "ghcr.io/gethomepage/homepage:v1.9.0";
    autoStart = true;

    extraOptions = [
      "--health-cmd=none"
      "--cap-add=NET_RAW"
      "--dns=${config.homelab.ips.gw}"
    ];

    environment = {
      TZ = tz;
      HOMEPAGE_ALLOWED_HOSTS = "*";
      PUID = puid;
      PGID = pgid;
    };

    environmentFiles = [ config.sops.templates."homepage".path ];

    volumes = [ "${cfgDir}:/app/config" "/srv:/srv:ro,rslave" ];

    ports = [ "${listenHost}:${toString listenPort}:3000" ];
  };

  systemd.services.podman-homepage = {
    after =
      [ "homepage-config.service" "network-online.target" "srv-media.mount" ];
    requires = [ "homepage-config.service" "srv-media.mount" ];
    unitConfig.RequiresMountsFor = [ "/srv/media" ];
  };
}
