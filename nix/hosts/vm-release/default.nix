{ lib, config, ... }:

let
  ips = config.homelab.ips;
  # Mirrors local.admin_hosts in infra/router/locals.tf; the router allows SSH
  # into VLAN 31 from this address only.
  adminHost = "192.168.1.74";
in {
  imports = [ ../../profiles/base ../../services/ci-runner ];

  # Trusted tier: registered only to the release repository, whose single
  # workflow builds, publishes and deploys merged main. Pull requests in the
  # application repository cannot reach this runner, because GitHub only hands
  # it jobs from that one repository.
  homelab.ciRunner = {
    repo = "shakirware/locum-shifts-release";
    labels = "vm-release";
    # Releases are rare and their jobs run in sequence.
    count = 1;
    namePrefix = "vm-release";
    # A Next.js production build needs most of this.
    memoryHigh = "4G";
    memoryMax = "4500M";
  };

  # VLAN 31 is internet only: no AdGuard, no Loki, no IPv6 (infra/router/release.tf).
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:5c:b6:a1";
    networkConfig = {
      DHCP = "no";
      Address = [ "${ips.release}/24" ];
      Gateway = ips.router_vlan31;
      DNS = [ "1.1.1.1" "9.9.9.9" ];
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
    };
  };
  networking.nameservers = lib.mkForce [ "1.1.1.1" "9.9.9.9" ];
  networking.enableIPv6 = false;

  # Loki is not reachable from VLAN 31; logs stay in the local journal.
  services.alloy.enable = lib.mkForce false;
  services.journald.extraConfig = "SystemMaxUse=1G";

  # SSH from the admin workstation only (the router enforces the same).
  networking.nftables.tables."ssh-guard" = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -50; policy accept;
        tcp dport 22 jump ssh_guard
      }

      chain ssh_guard {
        ct state established,related accept
        ip saddr ${adminHost} accept
        drop
      }
    '';
  };

  # Image builds write and delete gigabytes; hand freed blocks back to the
  # Proxmox thin pool (the disk has discard=on).
  services.fstrim = {
    enable = true;
    interval = "daily";
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  sops = {
    defaultSopsFile = ../../../secrets/vm-release.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
