{ config, pkgs, ... }:

let
  tz = "Europe/London";
  puid = "1000";
  pgid = "1001";

  ips = config.homelab.ips;

  mediaIp = ips.media;
  proxmoxIp = ips.proxmox;
  routerIp = ips.router;

  baseDomain = config.homelab.baseDomain;

  # Hostnames (served via Caddy)
  homepageHost = "homepage.${baseDomain}";
  adguardHost = "adguard.${baseDomain}";
  jellyfinHost = "jellyfin.${baseDomain}";
  jellyseerrHost = "jellyseerr.${baseDomain}";
  jellystatHost = "jellystat.${baseDomain}";
  sonarrHost = "sonarr.${baseDomain}";
  radarrHost = "radarr.${baseDomain}";
  profilarrHost = "profilarr.${baseDomain}";
  cleanuparrHost = "cleanuparr.${baseDomain}";
  qbittorrentHost = "qbittorrent.${baseDomain}";
  prowlarrHost = "prowlarr.${baseDomain}";
  tuliproxHost = "tuliprox.${baseDomain}";

  # Infra hostnames
  proxmoxHost = "proxmox.${baseDomain}";
  routerHost = "router.${baseDomain}";
  storageHost = "storage.${baseDomain}";
  mediaHost = "media.${baseDomain}";

  cfgDir = "/srv/appdata/homepage";

  settingsYaml = ./homepage/settings.yaml;
  widgetsYaml = ./homepage/widgets.yaml;
  servicesTmpl = ./homepage/services.yaml.tmpl;
in {
  systemd.tmpfiles.rules = [ "d ${cfgDir} 2775 shakir media - -" ];

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

      install -d -m 2775 -o shakir -g media ${cfgDir}

      install -m 0664 -o ${puid} -g ${pgid} ${settingsYaml} ${cfgDir}/settings.yaml
      install -m 0664 -o ${puid} -g ${pgid} ${widgetsYaml}  ${cfgDir}/widgets.yaml

      sed \
        -e "s|__MEDIA_IP__|${mediaIp}|g" \
        -e "s|__ADGUARD_HOST__|${adguardHost}|g" \
        -e "s|__PROXMOX_IP__|${proxmoxIp}|g" \
        -e "s|__ROUTER_IP__|${routerIp}|g" \
        -e "s|__BASE_DOMAIN__|${baseDomain}|g" \
        -e "s|__HOMEPAGE_HOST__|${homepageHost}|g" \
        -e "s|__JELLYFIN_HOST__|${jellyfinHost}|g" \
        -e "s|__JELLYSEERR_HOST__|${jellyseerrHost}|g" \
        -e "s|__JELLYSTAT_HOST__|${jellystatHost}|g" \
        -e "s|__SONARR_HOST__|${sonarrHost}|g" \
        -e "s|__RADARR_HOST__|${radarrHost}|g" \
        -e "s|__PROFILARR_HOST__|${profilarrHost}|g" \
        -e "s|__CLEANUPARR_HOST__|${cleanuparrHost}|g" \
        -e "s|__QBITTORRENT_HOST__|${qbittorrentHost}|g" \
        -e "s|__PROWLARR_HOST__|${prowlarrHost}|g" \
        -e "s|__TULIPROX_HOST__|${tuliproxHost}|g" \
        -e "s|__PROXMOX_HOST__|${proxmoxHost}|g" \
        -e "s|__ROUTER_HOST__|${routerHost}|g" \
        -e "s|__STORAGE_HOST__|${storageHost}|g" \
        -e "s|__MEDIA_HOST__|${mediaHost}|g" \
        ${servicesTmpl} > ${cfgDir}/services.yaml

      chown ${puid}:${pgid} ${cfgDir}/services.yaml
      chmod 0664 ${cfgDir}/services.yaml
    '';
  };

  virtualisation.oci-containers.containers.homepage = {
    image = "ghcr.io/gethomepage/homepage:v1.8.0";
    autoStart = true;

    extraOptions = [ "--health-cmd=none" ];

    environment = {
      TZ = tz;
      HOMEPAGE_ALLOWED_HOSTS = "*";
      PUID = puid;
      PGID = pgid;
    };

    volumes = [ "${cfgDir}:/app/config" "/srv:/srv:ro" ];
    ports = [ "127.0.0.1:3000:3000" ];
  };

  systemd.services.podman-homepage = {
    after = [ "homepage-config.service" ];
    requires = [ "homepage-config.service" ];
  };
}
