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

  mediaIp = ips.media;
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

  settingsYaml = ./config/settings.yaml;
  widgetsYaml = ./config/widgets.yaml;
  servicesTmpl = ./config/services.yaml.tmpl;
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

    path = [ pkgs.coreutils pkgs.gnused ];

    script = ''
      set -euo pipefail

      install -d -m 2775 -o ${config.homelab.ids.user} -g media ${cfgDir}

      install -m 0664 -o ${puid} -g ${pgid} ${settingsYaml} ${cfgDir}/settings.yaml
      install -m 0664 -o ${puid} -g ${pgid} ${widgetsYaml}  ${cfgDir}/widgets.yaml

      sed \
        -e "s|__GW_IP__|${ips.gw}|g" \
        -e "s|__MEDIA_IP__|${mediaIp}|g" \
        -e "s|__PROXMOX_IP__|${proxmoxIp}|g" \
        -e "s|__ROUTER_IP__|${routerIp}|g" \
        -e "s|__BASE_DOMAIN__|${baseDomain}|g" \
        -e "s|__HOMEPAGE_HOST__|${homepageHost}|g" \
        -e "s|__ADGUARD_HOST__|${adguardHost}|g" \
        -e "s|__UPTIME_HOST__|${uptimeHost}|g" \
        -e "s|__JELLYFIN_HOST__|${jellyfinHost}|g" \
        -e "s|__JELLYSEERR_HOST__|${jellyseerrHost}|g" \
        -e "s|__JELLYSTAT_HOST__|${jellystatHost}|g" \
        -e "s|__SONARR_HOST__|${sonarrHost}|g" \
        -e "s|__RADARR_HOST__|${radarrHost}|g" \
        -e "s|__PROWLARR_HOST__|${prowlarrHost}|g" \
        -e "s|__QBITTORRENT_HOST__|${qbittorrentHost}|g" \
        -e "s|__IPTV_HOST__|${iptvHost}|g" \
        -e "s|__PROXMOX_HOST__|${proxmoxHost}|g" \
        -e "s|__ROUTER_HOST__|${routerHost}|g" \
        -e "s|__STORAGE_HOST__|${storageHost}|g" \
        -e "s|__MEDIA_HOST__|${mediaHost}|g" \
        -e "s|__PROFILARR_HOST__|${profilarrHost}|g" \
        ${servicesTmpl} > ${cfgDir}/services.yaml

      chown ${puid}:${pgid} ${cfgDir}/services.yaml
      chmod 0664 ${cfgDir}/services.yaml
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
