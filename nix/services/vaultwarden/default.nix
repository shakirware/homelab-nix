{ config, lib, ... }:

let
  port = 8222;

  dataDir = "/var/lib/vaultwarden";

  gwIp = config.homelab.ips.gw;
in {
  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";

    config = {
      DOMAIN = "https://vault.${config.homelab.baseDomain}";

      ROCKET_ADDRESS = "0.0.0.0";
      ROCKET_PORT = port;

      # Re-enable briefly to add another account.
      SIGNUPS_ALLOWED = false;
      # Invitations need SMTP, which is not configured.
      INVITATIONS_ALLOWED = false;
      SHOW_PASSWORD_HINT = false;

      # No ADMIN_TOKEN: the /admin panel stays disabled.
    };
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  homelab.firewall.restrict.${toString port} = [ gwIp ];

  homelab.backup = {
    paths = [ dataDir ];
    exclude = [
      "${dataDir}/db.sqlite3"
      "${dataDir}/db.sqlite3-wal"
      "${dataDir}/db.sqlite3-shm"
      "${dataDir}/icon_cache"
    ];
    sqlite = [ "${dataDir}/db.sqlite3" ];
  };
}
