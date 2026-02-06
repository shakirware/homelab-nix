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
    owner = "root";
    group = "root";
    mode = "0444"; # or "0644"
  };

  virtualisation.oci-containers.containers.proxmox_exporter = {
    image = "prompve/prometheus-pve-exporter:3.4.1";
    autoStart = true;

    volumes = [
      "${config.sops.templates.${pveCfgName}.path}:/etc/prometheus/pve.yml:ro"
    ];

    extraOptions = [ "--network=host" "--name=proxmox-exporter" ];
  };

  systemd.services.podman-proxmox_exporter = {
    after = [ "podman.service" ];
    requires = [ "podman.service" ];
  };
}
