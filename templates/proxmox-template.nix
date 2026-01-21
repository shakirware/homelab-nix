{ lib, pkgs, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"

    ../nix/modules/networking/default.nix

    ../nix/modules/users/ids.nix
    ../nix/modules/users/default.nix
    ../nix/modules/users/dirs.nix
  ];

  networking.hostName = "nixos-template";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "shakir" ];
  };

  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";

  services.openssh.enable = true;
  services.openssh.openFirewall = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [ git vim curl jq ];

  virtualisation.diskSize = 8192;

  services.getty.autologinUser = lib.mkForce null;

  boot.kernelParams = [ "console=tty0" ];

  system.stateVersion = "25.11";
}
