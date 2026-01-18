{
  services.tailscale.enable = true;

  # TODO: pihole/dns later

  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
}
