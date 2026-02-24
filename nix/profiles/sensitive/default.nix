{ ... }:

{
  virtualisation.podman = {
    enable = true;
    defaultNetwork.settings.dns_enabled = true;
  };

  virtualisation.oci-containers.backend = "podman";

  imports = [
    ../../services/actual
    ../../services/standardnotes
    ../../services/invoiceplane
  ];
}
