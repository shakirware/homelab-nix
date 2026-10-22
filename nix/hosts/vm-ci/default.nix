{ lib, config, ... }:

let
  ips = config.homelab.ips;
  # Mirrors local.admin_hosts in infra/router/locals.tf; the router allows SSH
  # into VLAN 30 from this address only.
  adminHost = "192.168.1.74";
in {
  imports = [ ../../profiles/base ../../services/ci-runner ];

  # VLAN 30 is internet only: no AdGuard, no Loki, no IPv6 (infra/router/ci.tf).
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:c8:de:fa";
    networkConfig = {
      DHCP = "no";
      Address = [ "${ips.ci}/24" ];
      Gateway = ips.router_vlan30;
      DNS = [ "1.1.1.1" "9.9.9.9" ];
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
    };
  };
  networking.nameservers = lib.mkForce [ "1.1.1.1" "9.9.9.9" ];
  networking.enableIPv6 = false;

  # Loki is not reachable from VLAN 30; logs stay in the local journal.
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

  # Hands freed blocks back to the Proxmox thin pool (the disk has discard=on).
  # Daily: CI writes and deletes gigabytes per run; one afternoon of that left
  # 13 GiB allocated in the pool that the guest no longer used.
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
    defaultSopsFile = ../../../secrets/vm-ci.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };
}
