{ ... }: {
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  imports = [ ../../services/obsidian-livesync ];
}
