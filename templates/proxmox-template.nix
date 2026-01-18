{ lib, ... }:

{
  imports = [ ../modules/common/base.nix ../modules/common/networking.nix ];

  networking.hostName = "nixos-template";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "shakir" ];
  };

  virtualisation.diskSize = 8192;

  services.qemuGuest.enable = true;

  systemd.network.networks."10-lan" = {
    matchConfig.Name = "ens18";
    networkConfig.DHCP = "yes";
  };

  services.getty.autologinUser = lib.mkForce null;
  boot.kernelParams = [ "console=tty0" ];
}
