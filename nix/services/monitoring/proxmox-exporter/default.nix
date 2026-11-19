{ config, lib, ... }:

let
  port = 9221;
  pveCfgName = "pve.yml";
in {
  sops.secrets."proxmox/user" = { };
  sops.secrets."proxmox/token_name" = { };
  sops.secrets."proxmox/token_value" = { };

  sops.templates.${pveCfgName} = {
    content = ''
      default:
        user: "${config.sops.placeholder."proxmox/user"}"
        token_name: "${config.sops.placeholder."proxmox/token_name"}"
        token_value: "${config.sops.placeholder."proxmox/token_value"}"
        verify_ssl: false
    '';
    # The exporter image runs as uid/gid 101 (prometheus) with no user-namespace
    # remapping, so a root-owned 0400 file would be unreadable inside the
    # container.  Own the rendered file by that id instead of making it
    # world-readable, mirroring how the alertmanager template targets its own
    # container user.  Keep in sync with the image's prometheus uid.
    uid = 101;
    gid = 101;
    mode = "0400";
    restartUnits = [ "podman-proxmox_exporter.service" ];
  };

  virtualisation.oci-containers.containers.proxmox_exporter = {
    image = "prompve/prometheus-pve-exporter:3.12.0@sha256:e49466559449074596e762dd09c9a76c9be9b6a1ffacf7bc8ceb827169cb180e";
    volumes = [
      "${config.sops.templates.${pveCfgName}.path}:/etc/prometheus/pve.yml:ro"
    ];

    extraOptions = [ "--network=host" "--name=proxmox-exporter" ];
  };

  systemd.services."podman-proxmox_exporter" = {
    after = [ "podman.service" ];
    requires = [ "podman.service" ];
  };
}
