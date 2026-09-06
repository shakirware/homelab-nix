{ ... }:

{
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  imports = [
    ../../services/nfs-client

    ../../services/jellyfin
    ../../services/seerr
    ../../services/tracearr

    ../../services/sonarr
    ../../services/radarr
    ../../services/prowlarr
    ../../services/flaresolverr

    ../../services/shelfmark
    ../../services/readmeabook
    ../../services/grimmory
    ../../services/audiobookshelf

    ../../services/gluetun
    ../../services/qbittorrent

    ../../services/profilarr
    ../../services/cleanuparr

    ../../services/tuliprox

    ../../services/pinchflat

    ../../services/netv
  ];
}
