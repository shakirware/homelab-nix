{ lib, pkgs, modulesPath, ... }:

{
  imports = [
    "${modulesPath}/profiles/qemu-guest.nix"

    ../../modules/common/addresses.nix
    ../../modules/hardware/proxmox.nix

    ../../modules/users/ids.nix
    ../../modules/users/default.nix
    ../../modules/users/dirs.nix

    ../../modules/networking/default.nix

    ../../modules/dns/domains.nix
    ../../modules/dns/records.nix
    ../../modules/dns/adguard-rewrites.nix

    ../../modules/secrets/sops-base.nix
    ../../modules/secrets/host-secrets.nix
    ../../modules/secrets/templates.nix
  ];

  services.qemuGuest.enable = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "shakir" ];
  };

  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";

  homelab.baseDomain = lib.mkDefault "shakr.dev";

  services.openssh.enable = true;
  services.openssh.openFirewall = true;
  services.openssh.settings = {
    PasswordAuthentication = false;
    KbdInteractiveAuthentication = false;
    PermitRootLogin = "no";
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [ git vim curl jq dnsutils bind ];

  system.stateVersion = "25.11";
}
