{ ... }:

{
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  homelab.secrets.envTemplates."caddy-cloudflare" = {
    env = { CLOUDFLARE_API_TOKEN = "CLOUDFLARE_API_TOKEN"; };
  };

  imports = [
    ../../services/tailscale
    ../../services/unbound
    ../../services/adguard

    ../../services/homepage

    ../../services/reverse-proxy
  ];
}
