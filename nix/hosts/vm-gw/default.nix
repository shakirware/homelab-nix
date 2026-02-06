{ config, ... }:

let ips = config.homelab.ips;
in {
  imports =
    [ ../../profiles/base ../../profiles/ops ../../services/nfs-client ];

  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "bc:24:11:b5:da:e2";
    networkConfig = {
      DHCP = "no";
      Address = [ "${ips.gw}/24" ];
      Gateway = ips.router;
      DNS = [ ips.gw ];
    };
  };

  sops = {
    defaultSopsFile = ../../../secrets/vm-gw.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  homelab.secrets.envTemplates.homepage = {
    env = {
      HOMEPAGE_VAR_QBITTORRENT_USER = "HOMEPAGE_VAR_QBITTORRENT_USER";
      HOMEPAGE_VAR_QBITTORRENT_PASS = "HOMEPAGE_VAR_QBITTORRENT_PASS";

      HOMEPAGE_VAR_JELLYFIN_KEY = "HOMEPAGE_VAR_JELLYFIN_KEY";
      HOMEPAGE_VAR_JELLYSEERR_KEY = "HOMEPAGE_VAR_JELLYSEERR_KEY";
      HOMEPAGE_VAR_JELLYSTAT_KEY = "HOMEPAGE_VAR_JELLYSTAT_KEY";

      HOMEPAGE_VAR_SONARR_KEY = "HOMEPAGE_VAR_SONARR_KEY";
      HOMEPAGE_VAR_RADARR_KEY = "HOMEPAGE_VAR_RADARR_KEY";
      HOMEPAGE_VAR_PROWLARR_KEY = "HOMEPAGE_VAR_PROWLARR_KEY";

      HOMEPAGE_VAR_ADGUARD_USER = "HOMEPAGE_VAR_ADGUARD_USER";
      HOMEPAGE_VAR_ADGUARD_PASS = "HOMEPAGE_VAR_ADGUARD_PASS";

      HOMEPAGE_VAR_PROXMOX_TOKEN = "HOMEPAGE_VAR_PROXMOX_TOKEN";
      HOMEPAGE_VAR_PROXMOX_SECRET = "HOMEPAGE_VAR_PROXMOX_SECRET";

      HOMEPAGE_VAR_GRAFANA_USER = "HOMEPAGE_VAR_GRAFANA_USER";
      HOMEPAGE_VAR_GRAFANA_PASS = "HOMEPAGE_VAR_GRAFANA_PASS";
    };
  };
}
