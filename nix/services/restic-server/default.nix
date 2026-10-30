{ config, lib, ... }:

let
  port = 8000;

  # Outside the mergerfs branches and the NFS export.
  diskDir = "/srv/diskB";
  dataDir = "${diskDir}/restic";

  ips = config.homelab.ips;

  # One htpasswd user and private repo per client, named after the host.
  clients = [ ips.apps ips.media ips.sensitive ];

  htpasswdName = "restic-htpasswd";

  # Self-signed, valid to 2036; clients trust it via RESTIC_CACERT.
  tlsCert = ./tls.crt;
in {
  sops.secrets."restic/htpasswd" = { };

  sops.secrets."restic/tls_key" = {
    owner = "restic";
    group = "restic";
    mode = "0400";
    restartUnits = [ "restic-rest-server.service" ];
  };

  sops.templates.${htpasswdName} = {
    content = config.sops.placeholder."restic/htpasswd";
    owner = "restic";
    group = "restic";
    mode = "0400";
    restartUnits = [ "restic-rest-server.service" ];
  };

  # Append-only: clients can add snapshots but never remove them.
  services.restic.server = {
    enable = true;
    inherit dataDir;
    listenAddress = toString port;
    appendOnly = true;
    privateRepos = true;
    htpasswd-file = config.sops.templates.${htpasswdName}.path;
    extraFlags = [
      "--tls"
      "--tls-cert"
      "${tlsCert}"
      "--tls-key"
      config.sops.secrets."restic/tls_key".path
    ];
  };

  systemd.tmpfiles.rules = lib.mkAfter [ "d ${dataDir} 0700 restic restic - -" ];

  systemd.services.restic-rest-server.unitConfig.RequiresMountsFor =
    [ dataDir ];
  systemd.sockets.restic-rest-server.unitConfig.RequiresMountsFor =
    [ diskDir ];

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  # Only the backup clients may reach the REST server.
  networking.nftables.tables."restic-server-guard" = {
    family = "inet";

    content = ''
      chain input {
        type filter hook input priority -50; policy accept;
        tcp dport ${toString port} jump restic_guard
      }

      chain restic_guard {
        ct state established,related accept
        iifname "lo" accept
        ip saddr { ${lib.concatStringsSep ", " clients} } accept
        drop
      }
    '';
  };
}
