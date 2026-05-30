{ config, lib, ... }:

let ips = config.homelab.ips;
in {
  imports = [ ../../profiles/base ../../profiles/media ];

  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:bb:ac:8b";
    networkConfig = {
      DHCP = "no";
      Address = [ "${ips.media}/24" ];
      Gateway = ips.router_vlan20;
      DNS = [ ips.gw ];
    };
  };

  fileSystems."/srv/downloads" = {
    device = "/dev/disk/by-uuid/92877cc5-ee1b-4d44-9e6e-8c3392cc80b9";
    fsType = "ext4";
    options = [
      "nofail"
      "noatime"
      "discard"
      "x-systemd.device-timeout=30"
    ];
  };

  systemd.tmpfiles.rules = lib.mkAfter [
    "d /srv/downloads 2775 ${config.homelab.ids.user} media - -"
    "d /srv/downloads/complete 2775 ${config.homelab.ids.user} media - -"
    "d /srv/downloads/incomplete 2775 ${config.homelab.ids.user} media - -"
    "d /srv/downloads/torrents 2775 ${config.homelab.ids.user} media - -"
  ];

  systemd.services.podman-qbittorrent.unitConfig.RequiresMountsFor =
    lib.mkAfter [ "/srv/downloads" ];

  systemd.services.podman-sonarr.unitConfig.RequiresMountsFor =
    lib.mkAfter [ "/srv/downloads" ];

  systemd.services.podman-radarr.unitConfig.RequiresMountsFor =
    lib.mkAfter [ "/srv/downloads" ];

  systemd.services.podman-cleanuparr.unitConfig.RequiresMountsFor =
    lib.mkAfter [ "/srv/downloads" ];

  sops = {
    defaultSopsFile = ../../../secrets/vm-media.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  homelab.secrets.envTemplates."iptv-proxy" = {
    env = { M3U_URL_1 = "iptv/m3u_url_1"; };
  };
}
