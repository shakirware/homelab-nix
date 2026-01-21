{ config, ... }:

let ips = config.homelab.ips;
in {
  imports = [ ../../profiles/base ../../profiles/media ];

  systemd.network.networks."10-lan" = {
    matchConfig.Name = "ens18";
    networkConfig = {
      DHCP = "no";
      Address = [ "${ips.media}/24" ];
      Gateway = ips.router;

      DNS = [ ips.gw ];
    };
  };

  sops = {
    defaultSopsFile = ../../../secrets/vm-media.yaml;
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  sops.secrets."jellystat/postgres_password" = { };
  sops.secrets."jellystat/jwt_secret" = { };

  sops.templates."jellystat-db.env".content = ''
    POSTGRES_PASSWORD=${config.sops.placeholder."jellystat/postgres_password"}
  '';

  sops.templates."jellystat.env".content = ''
    POSTGRES_PASSWORD=${config.sops.placeholder."jellystat/postgres_password"}
    JWT_SECRET=${config.sops.placeholder."jellystat/jwt_secret"}
  '';
}
