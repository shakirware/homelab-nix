{ ... }: {
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  imports = [
    ../../services/nfs-client
    ../../services/monitoring/mount-probe

    ../../services/obsidian-livesync
    ../../services/home-assistant
    ../../services/yamtrack
    ../../services/kaneo
  ];
}
