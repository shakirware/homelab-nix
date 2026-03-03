{ ... }:

{
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  imports = [
    ../../services/nfs-client

    ../../services/jellyfin
    ../../services/seerr
    ../../services/jellystat
    ../../services/tracearr

    ../../services/sonarr
    ../../services/radarr
    ../../services/prowlarr
    ../../services/flaresolverr

    ../../services/gluetun
    ../../services/qbittorrent

    ../../services/profilarr
    ../../services/tuliprox
  ];
}
