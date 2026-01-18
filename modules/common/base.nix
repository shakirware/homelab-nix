{ pkgs, modulesPath, ... }:

{
  imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];
  services.qemuGuest.enable = true;

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

  users.groups.media.gid = 1001;
  users.users.shakir = {
    isNormalUser = true;
    extraGroups = [ "wheel" "media" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMgak38Af+nKukrQHPyqtqrl6VI/vEhivai6+0KrASTV shakir@homelab"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  environment.systemPackages = with pkgs; [ git vim curl jq dnsutils bind ];

  system.stateVersion = "25.11";
}
