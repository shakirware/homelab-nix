{ ... }: {
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
    ../../services/monitoring/mount-probe

    ../../services/obsidian-livesync
    ../../services/home-assistant
    ../../services/yamtrack
    ../../services/kaneo
    ../../services/immich
  ];
}
