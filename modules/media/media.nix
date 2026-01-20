{
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  imports = [
    ./mounts.nix
    ./dirs.nix
    ./containers.nix
    ./jellystat-net.nix
    ./vpn-net.nix
    ./homepage.nix
    ./caddy.nix
  ];
}
