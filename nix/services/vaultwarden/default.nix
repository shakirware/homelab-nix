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

      # Leave enabled for first account creation, then set to false.
      SIGNUPS_ALLOWED = true;
      # Invitations need SMTP, which is not configured.
      INVITATIONS_ALLOWED = false;
      SHOW_PASSWORD_HINT = false;

      # No ADMIN_TOKEN: the /admin panel stays disabled.
    };
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  # Only the gateway/reverse proxy may access Vaultwarden directly.
  networking.nftables.tables."vaultwarden-backend-guard" = {
    family = "inet";
    content = ''
      chain prerouting {
        type filter hook prerouting priority -150; policy accept;
        fib daddr type local tcp dport ${toString port} jump vaultwarden_guard
      }

      chain vaultwarden_guard {
        ct state established,related accept
        iifname "lo" accept
        ip saddr ${gwIp} accept
        drop
      }
    '';
  };

  # The vault database via .backup; attachments, sends, icons cache and the
  # RSA key used to sign logins as files.
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
