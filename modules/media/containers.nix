{ config, pkgs, lib, ... }:

let
  images = {
    jellyfin = "lscr.io/linuxserver/jellyfin:version-10.11.5ubu2404";
    qbittorrent = "lscr.io/linuxserver/qbittorrent:version-5.1.4-r1";
    sonarr = "lscr.io/linuxserver/sonarr:version-4.0.16.2944";
    radarr = "lscr.io/linuxserver/radarr:version-6.0.4.10291";
    prowlarr = "lscr.io/linuxserver/prowlarr:version-2.3.0.5236";
    jellyseerr = "ghcr.io/fallenbagel/jellyseerr:2.7.3";
    jellystatDb = "postgres:15.2";
    jellystat = "cyfershepard/jellystat:1.1.7";
    profilarr = "santiagosayshey/profilarr:v1.1.3";
    tuliprox = "ghcr.io/euzu/tuliprox:3.2.0";
    cleanuparr = "ghcr.io/cleanuparr/cleanuparr:2.5.1";
  };

  tz = "Europe/London";
  puid = "1000";
  pgid = "1001";

  # Bind application ports to localhost only.
  # Caddy (80/443) is the only thing exposed to the LAN.
  lanIp = "127.0.0.1";

  jellystatNet = "jellystat-net";
  dbIp = "10.90.0.2";
  appIp = "10.90.0.3";

  vpnNet = "vpn-net";
in {
  environment.systemPackages = with pkgs; [ nfs-utils ];

  virtualisation.oci-containers.containers.gluetun = {
    image = "qmcgaw/gluetun:v3.41.0";
    autoStart = true;

    extraOptions =
      [ "--network=${vpnNet}" "--cap-add=NET_ADMIN" "--device=/dev/net/tun" ];

    # Only bound locally; Caddy proxies to these via 127.0.0.1
    ports = [
      "${lanIp}:8080:8080"
      "${lanIp}:6881:6881"
      "${lanIp}:6881:6881/udp"
      "${lanIp}:9696:9696"
      "${lanIp}:8901:8901"
    ];

    environment = {
      VPN_SERVICE_PROVIDER = "mullvad";
      VPN_TYPE = "wireguard";
      IPV6 = "off";

      # This is inside the container; keep as-is
      FIREWALL_OUTBOUND_SUBNETS = "192.168.0.0/16";
      FIREWALL_INPUT_PORTS = "8080,9696,6881,8901";
    };

    volumes = [ "/srv/appdata/gluetun:/gluetun" ];
  };

  virtualisation.oci-containers.containers.jellyfin = {
    image = images.jellyfin;
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
    };

    volumes = [ "/srv/appdata/jellyfin:/config" "/srv/media:/data" ];

    ports = [
      "${lanIp}:8096:8096"
      # Discovery is UDP; keep local-only (Caddy doesn't need this).
      "${lanIp}:7359:7359/udp"
    ];

    extraOptions = [ "--device=/dev/dri:/dev/dri" ];
  };

  virtualisation.oci-containers.containers.qbittorrent = {
    image = images.qbittorrent;
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
      WEBUI_PORT = "8080";
    };

    volumes = [ "/srv/appdata/qbittorrent:/config" "/srv/downloads:/data" ];

    ports = [ ];
    extraOptions = [ "--network=container:gluetun" ];
  };

  virtualisation.oci-containers.containers.sonarr = {
    image = images.sonarr;
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
    };

    volumes = [
      "/srv/appdata/sonarr:/config"
      "/srv/downloads:/downloads"
      "/srv/media:/media"
    ];

    ports = [ "${lanIp}:8989:8989" ];
  };

  virtualisation.oci-containers.containers.radarr = {
    image = images.radarr;
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
    };

    volumes = [
      "/srv/appdata/radarr:/config"
      "/srv/downloads:/downloads"
      "/srv/media:/media"
    ];

    ports = [ "${lanIp}:7878:7878" ];
  };

  virtualisation.oci-containers.containers.prowlarr = {
    image = images.prowlarr;
    autoStart = true;

    environment = {
      PUID = puid;
      PGID = pgid;
      TZ = tz;
    };

    volumes = [ "/srv/appdata/prowlarr:/config" ];
    ports = [ ];
    extraOptions = [ "--network=container:gluetun" ];
  };

  virtualisation.oci-containers.containers.jellyseerr = {
    image = images.jellyseerr;
    autoStart = true;

    environment = {
      TZ = tz;
      PORT = "5055";
    };

    volumes = [ "/srv/appdata/jellyseerr:/app/config" ];

    ports = [ "${lanIp}:5055:5055" ];
  };

  virtualisation.oci-containers.containers.jellystat-db = {
    image = images.jellystatDb;
    autoStart = true;

    environment = {
      POSTGRES_USER = "postgres";
      POSTGRES_DB = "jellystat";
    };

    environmentFiles = [ config.sops.templates."jellystat-db.env".path ];

    volumes =
      [ "/srv/appdata/jellystat/postgres-data:/var/lib/postgresql/data" ];

    extraOptions =
      [ "--network=${jellystatNet}" "--ip=${dbIp}" "--name=jellystat-db" ];
  };

  virtualisation.oci-containers.containers.jellystat = {
    image = images.jellystat;
    autoStart = true;

    environment = {
      POSTGRES_USER = "postgres";
      POSTGRES_IP = dbIp;
      POSTGRES_PORT = "5432";
      TZ = tz;
    };

    environmentFiles = [ config.sops.templates."jellystat.env".path ];

    volumes = [ "/srv/appdata/jellystat:/app/backend/backup-data" ];

    ports = [ "${lanIp}:4001:3000" ];

    extraOptions =
      [ "--network=${jellystatNet}" "--ip=${appIp}" "--name=jellystat" ];
  };

  virtualisation.oci-containers.containers.profilarr = {
    image = images.profilarr;
    autoStart = true;

    environment = { TZ = tz; };
    volumes = [ "/srv/appdata/profilarr:/config" ];

    ports = [ "${lanIp}:6868:6868" ];
  };

  virtualisation.oci-containers.containers.tuliprox = {
    image = images.tuliprox;
    autoStart = true;

    environment = { TZ = tz; };

    ports = [ ];
    extraOptions = [ "--network=container:gluetun" ];

    volumes = [
      "/srv/appdata/tuliprox/config/config.yml:/app/config.yml:ro"
      "/srv/appdata/tuliprox/config/source.yml:/app/source.yml:ro"
      "/srv/appdata/tuliprox/config/api-proxy.yml:/app/api-proxy.yml:ro"
      "/srv/appdata/tuliprox/data:/data"
      "/srv/appdata/tuliprox/backup:/backup"
      "/srv/appdata/tuliprox/downloads:/downloads"
    ];
  };

  virtualisation.oci-containers.containers.cleanuparr = {
    image = images.cleanuparr;
    autoStart = true;

    environment = {
      PORT = "11011";
      PUID = puid;
      PGID = pgid;
      TZ = tz;
    };

    volumes = [
      "/srv/appdata/cleanuparr:/config"
      "/srv/appdata/sonarr:/sonarr:ro"
      "/srv/appdata/radarr:/radarr:ro"
    ];

    ports = [ "${lanIp}:11011:11011" ];
  };

  systemd.services.podman-gluetun = {
    after = [ "podman-network-${vpnNet}.service" "podman.service" ];
    requires = [ "podman-network-${vpnNet}.service" "podman.service" ];
  };

  systemd.services.podman-qbittorrent = {
    after = [
      "podman-gluetun.service"
      "podman-network-${vpnNet}.service"
      "podman.service"
    ];
    requires = [
      "podman-gluetun.service"
      "podman-network-${vpnNet}.service"
      "podman.service"
    ];
  };

  systemd.services.podman-prowlarr = {
    after = [
      "podman-gluetun.service"
      "podman-network-${vpnNet}.service"
      "podman.service"
    ];
    requires = [
      "podman-gluetun.service"
      "podman-network-${vpnNet}.service"
      "podman.service"
    ];
  };

  systemd.services.podman-tuliprox = {
    after = [
      "podman-gluetun.service"
      "podman-network-${vpnNet}.service"
      "podman.service"
    ];
    requires = [
      "podman-gluetun.service"
      "podman-network-${vpnNet}.service"
      "podman.service"
    ];
  };

  systemd.services.podman-jellyfin.unitConfig.RequiresMountsFor =
    [ "/srv/media" ];
  systemd.services.podman-sonarr.unitConfig.RequiresMountsFor =
    [ "/srv/media" ];
  systemd.services.podman-radarr.unitConfig.RequiresMountsFor =
    [ "/srv/media" ];

  systemd.services.podman-jellyfin.after =
    [ "network-online.target" "srv-media.mount" ];
  systemd.services.podman-sonarr.after =
    [ "network-online.target" "srv-media.mount" ];
  systemd.services.podman-radarr.after =
    [ "network-online.target" "srv-media.mount" ];

}
