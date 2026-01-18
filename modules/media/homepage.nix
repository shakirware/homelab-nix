{ config, pkgs, lib, ... }:

let
  tz = "Europe/London";
  puid = "1000";
  pgid = "1001";

  ips = config.homelab.ips;

  mediaIp = ips.media;
  proxmoxIp = ips.proxmox;
  routerIp = ips.router;

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
        -e "s|__PROXMOX_IP__|${proxmoxIp}|g" \
        -e "s|__ROUTER_IP__|${routerIp}|g" \
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

  services.nginx.enable = true;
  services.nginx.recommendedProxySettings = true;

  services.nginx.virtualHosts."_" = {
    listen = [{
      addr = "0.0.0.0";
      port = 80;
    }];
    locations."/" = {
      proxyPass = "http://127.0.0.1:3000";
      proxyWebsockets = true;
    };
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ 80 ];
}
