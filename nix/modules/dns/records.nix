{ lib, config, ... }:

let
  base = config.homelab.baseDomain;
  ips = config.homelab.ips;
in {
  config.homelab.domains = lib.mkDefault ({
    "gw.${base}" = ips.gw;
    "storage.${base}" = ips.storage;
    "media.${base}" = ips.media;
    "apps.${base}" = ips.apps;
    "sensitive.${base}" = ips.sensitive;
    "monitoring.${base}" = ips.monitoring;
  } // lib.listToAttrs
    (map (h: lib.nameValuePair h.host ips.gw) config.homelab.webHosts));

  config.homelab.webHosts = lib.mkDefault [
    {
      host = "adguard.${base}";
      upstream = "127.0.0.1:3000";
    }
    {
      host = "homepage.${base}";
      upstream = "127.0.0.1:3001";
    }
    {
      host = "proxmox.${base}";
      upstream = "https://${ips.proxmox}:8006";
      upstreamTlsInsecure = true;
    }
    {
      host = "actual.${base}";
      upstream = "${ips.sensitive}:5006";
      probePath = "/health";
    }
    {
      host = "vault.${base}";
      upstream = "${ips.sensitive}:8222";
      probePath = "/alive";
    }
    {
      host = "invoice.${base}";
      upstream = "${ips.sensitive}:8088";
    }
    {
      host = "jellyfin.${base}";
      upstream = "${ips.media}:8096";
      probePath = "/health";
    }
    {
      host = "seerr.${base}";
      upstream = "${ips.media}:5055";
      probePath = "/api/v1/status";
    }
    {
      host = "shelfmark.${base}";
      upstream = "${ips.media}:8084";
      probePath = "/api/health";
    }
    {
      host = "readmeabook.${base}";
      upstream = "${ips.media}:3030";
      probePath = "/api/health";
    }
    {
      host = "grimmory.${base}";
      upstream = "${ips.media}:6060";
      probePath = "/api/v1/healthcheck";
    }
    {
      host = "audiobookshelf.${base}";
      upstream = "${ips.media}:13378";
      probePath = "/healthcheck";
    }
    {
      host = "sonarr.${base}";
      upstream = "${ips.media}:8989";
      probePath = "/ping";
    }
    {
      host = "radarr.${base}";
      upstream = "${ips.media}:7878";
      probePath = "/ping";
    }
    {
      host = "bazarr.${base}";
      upstream = "${ips.media}:6767";
      probePath = "/api/system/ping";
    }
    {
      host = "prowlarr.${base}";
      upstream = "${ips.media}:9696";
      probePath = "/ping";
    }
    {
      host = "qbittorrent.${base}";
      upstream = "${ips.media}:8080";
    }
    {
      host = "iptv.${base}";
      upstream = "${ips.media}:8901";
    }
    {
      host = "netv.${base}";
      upstream = "${ips.media}:8000";
    }
    {
      host = "profilarr.${base}";
      upstream = "${ips.media}:6869";
      probePath = "/api/v1/health";
    }
    {
      host = "obsidian-sync.${base}";
      upstream = "${ips.apps}:5984";
      probePath = "/_up";
      # CouchDB requires auth on every path; a 401 still proves it is serving.
      probeModule = "http_auth_required";
    }
    {
      host = "homeassistant.${base}";
      upstream = "${ips.apps}:8123";
      probePath = "/manifest.json";
    }
    {
      host = "yamtrack.${base}";
      upstream = "${ips.apps}:8000";
      probePath = "/health/";
    }
    {
      host = "kaneo.${base}";
      upstream = "${ips.apps}:5173";
      probePath = "/api/health";
    }
    {
      host = "mealie.${base}";
      upstream = "${ips.apps}:9000";
      probePath = "/api/app/about";
    }
    {
      host = "immich.${base}";
      upstream = "${ips.apps}:2283";
      maxBodySize = "50GB";
      probePath = "/api/server/ping";
    }
    {
      host = "notes.${base}";
      upstream = "${ips.sensitive}:3002";
    }
    {
      host = "notes-api.${base}";
      upstream = "${ips.sensitive}:3000";
      corsAllowOrigin = "https://notes.${base}";
      probePath = "/healthcheck";
    }
    {
      host = "notes-files.${base}";
      upstream = "${ips.sensitive}:3125";
      corsAllowOrigin = "https://notes.${base}";
      probePath = "/healthcheck";
    }
    {
      host = "grafana.${base}";
      upstream = "${ips.monitoring}:3000";
      probePath = "/api/health";
    }
    {
      host = "prometheus.${base}";
      upstream = "${ips.monitoring}:9090";
      probePath = "/-/healthy";
    }
    {
      host = "alertmanager.${base}";
      upstream = "${ips.monitoring}:9093";
      probePath = "/-/healthy";
    }
    {
      host = "loki.${base}";
      upstream = "${ips.monitoring}:3100";
      probePath = "/ready";
    }
    {
      host = "tracearr.${base}";
      upstream = "${ips.media}:3003";
      probePath = "/health";
    }
    {
      host = "router.${base}";
      upstream = "http://${ips.router_vlan1}";
    }
    {
      host = "cleanuparr.${base}";
      upstream = "${ips.media}:11011";
      probePath = "/health";
    }
    {
      host = "pinchflat.${base}";
      upstream = "${ips.media}:8945";
      probePath = "/healthcheck";
    }
  ];
}
