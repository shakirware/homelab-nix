{ ... }:

{
  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  imports = [
    ../../services/monitoring/prometheus
    ../../services/monitoring/grafana
    ../../services/monitoring/alertmanager
    ../../services/monitoring/loki
    ../../services/monitoring/proxmox-exporter
  ];
}
