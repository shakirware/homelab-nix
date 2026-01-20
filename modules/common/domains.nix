{ lib, config, ... }:

let
  base = config.homelab.baseDomain;
  ips = config.homelab.ips;
in {
  options.homelab.baseDomain = lib.mkOption {
    type = lib.types.str;
    default = "home.arpa";
    description = "Base DNS domain for homelab (e.g. home.arpa).";
  };

  options.homelab.domains = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "DNS map: hostname -> IP address.";
  };

  options.homelab.webHosts = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        host = lib.mkOption { type = lib.types.str; };
        upstream = lib.mkOption { type = lib.types.str; };
      };
    });
    default = [ ];
    description = "Reverse proxy hosts (Caddy): host -> upstream address.";
  };

  config.homelab.domains = lib.mkDefault {
    # Infra
    "router.${base}" = ips.router;
    "proxmox.${base}" = ips.proxmox;
    "storage.${base}" = ips.storage;
    "media.${base}" = ips.media;
    "adguard.${base}" = ips.media;

    # Web apps 
    "homepage.${base}" = ips.media;
    "jellyfin.${base}" = ips.media;
    "jellyseerr.${base}" = ips.media;
    "jellystat.${base}" = ips.media;

    "sonarr.${base}" = ips.media;
    "radarr.${base}" = ips.media;
    "profilarr.${base}" = ips.media;
    "cleanuparr.${base}" = ips.media;

    # Apps behind gluetun port forwards 
    "qbittorrent.${base}" = ips.media;
    "prowlarr.${base}" = ips.media;
    "tuliprox.${base}" = ips.media;
  };

  # Caddy routes 
  config.homelab.webHosts = lib.mkDefault [
    {
      host = "adguard.${base}";
      upstream = "${ips.gw}:3000";
    }
    {
      host = "homepage.${base}";
      upstream = "127.0.0.1:3000";
    }
    {
      host = "jellyfin.${base}";
      upstream = "127.0.0.1:8096";
    }
    {
      host = "jellyseerr.${base}";
      upstream = "127.0.0.1:5055";
    }
    {
      host = "jellystat.${base}";
      upstream = "127.0.0.1:4001";
    }

    {
      host = "sonarr.${base}";
      upstream = "127.0.0.1:8989";
    }
    {
      host = "radarr.${base}";
      upstream = "127.0.0.1:7878";
    }
    {
      host = "profilarr.${base}";
      upstream = "127.0.0.1:6868";
    }
    {
      host = "cleanuparr.${base}";
      upstream = "127.0.0.1:11011";
    }

    # gluetun forwarded ports 
    {
      host = "qbittorrent.${base}";
      upstream = "127.0.0.1:8080";
    }
    {
      host = "prowlarr.${base}";
      upstream = "127.0.0.1:9696";
    }
    {
      host = "tuliprox.${base}";
      upstream = "127.0.0.1:8901";
    }
  ];
}
