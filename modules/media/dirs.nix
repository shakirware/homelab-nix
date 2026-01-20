{ ... }: {
  systemd.tmpfiles.rules = [
    "d /srv/appdata 2775 shakir media - -"
    "d /srv/appdata/gluetun 2775 shakir media - -"
    "d /srv/downloads 2775 shakir media - -"
    "d /srv/appdata/homepage 2775 shakir media - -"
    "d /srv/appdata/jellyfin 2775 shakir media - -"
    "d /srv/appdata/qbittorrent 2775 shakir media - -"
    "d /srv/appdata/sonarr 2775 shakir media - -"
    "d /srv/appdata/radarr 2775 shakir media - -"
    "d /srv/appdata/prowlarr 2775 shakir media - -"
    "d /srv/appdata/jellyseerr 2775 shakir media - -"
    "d /srv/appdata/jellystat 2775 shakir media - -"
    "d /srv/appdata/jellystat/postgres-data 2775 shakir media - -"
    "d /srv/appdata/profilarr 2775 shakir media - -"
    "d /srv/appdata/tuliprox 2775 shakir media - -"
    "d /srv/appdata/tuliprox/config 2775 shakir media - -"
    "d /srv/appdata/tuliprox/data 2775 shakir media - -"
    "d /srv/appdata/tuliprox/backup 2775 shakir media - -"
    "d /srv/appdata/tuliprox/downloads 2775 shakir media - -"
    "d /srv/appdata/cleanuparr 2775 shakir media - -"
  ];
}
