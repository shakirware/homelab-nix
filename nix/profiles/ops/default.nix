{ ... }:

{
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  imports = [
    ../../services/tailscale
    ../../services/unbound
    ../../services/adguard

    ../../services/homepage

    ../../services/reverse-proxy
  ];
}
