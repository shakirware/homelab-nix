{ ... }:

{
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  systemd.oomd.enable = true;
  systemd.slices.machine.sliceConfig = {
    ManagedOOMMemoryPressure = "kill";
    ManagedOOMMemoryPressureLimit = "60%";
  };

  imports = [
    ../../services/nfs-client

    ../../services/jellyfin
    ../../services/seerr
    ../../services/tracearr

    ../../services/sonarr
    ../../services/radarr
    ../../services/bazarr
    ../../services/prowlarr
    ../../services/flaresolverr

    ../../services/shelfmark
    ../../services/readmeabook
    ../../services/grimmory
    ../../services/audiobookshelf

    ../../services/gluetun
    ../../services/qbittorrent

    ../../services/profilarr
    ../../services/profilarr-v2
    ../../services/cleanuparr

    ../../services/tuliprox

    ../../services/pinchflat

    ../../services/netv

    ../../services/monitoring/mount-probe
  ];

  homelab.firewall.allowLocalContainers = true;
}
