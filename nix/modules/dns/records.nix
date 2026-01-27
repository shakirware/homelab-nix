{ lib, config, ... }:

let
  base = config.homelab.baseDomain;
  ips = config.homelab.ips;
in {
  config.homelab.domains = lib.mkDefault {
    "router.${base}" = ips.router;
    "proxmox.${base}" = ips.gw;
    "gw.${base}" = ips.gw;
    "storage.${base}" = ips.storage;
    "media.${base}" = ips.media;
    "apps.${base}" = ips.apps;
    "sensitive.${base}" = ips.sensitive;
    "adguard.${base}" = ips.gw;
    "homepage.${base}" = ips.gw;
    "uptime.${base}" = ips.gw;
    "actual.${base}" = ips.gw;
    "jellyfin.${base}" = ips.gw;
    "jellyseerr.${base}" = ips.gw;
    "jellystat.${base}" = ips.gw;
    "profilarr.${base}" = ips.gw;
    "sonarr.${base}" = ips.gw;
    "radarr.${base}" = ips.gw;
    "prowlarr.${base}" = ips.gw;
    "qbittorrent.${base}" = ips.gw;
    "iptv.${base}" = ips.gw;
    "obsidian-sync.${base}" = ips.gw;
  };

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
    }
    {
      host = "jellyfin.${base}";
      upstream = "${ips.media}:8096";
    }
    {
      host = "jellyseerr.${base}";
      upstream = "${ips.media}:5055";
    }
    {
      host = "jellystat.${base}";
      upstream = "${ips.media}:4001";
    }
    {
      host = "sonarr.${base}";
      upstream = "${ips.media}:8989";
    }
    {
      host = "radarr.${base}";
      upstream = "${ips.media}:7878";
    }
    {
      host = "prowlarr.${base}";
      upstream = "${ips.media}:9696";
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
      host = "profilarr.${base}";
      upstream = "${ips.media}:6868";
    }
    {
      host = "obsidian-sync.${base}";
      upstream = "${ips.apps}:5984";
    }
  ];
}
