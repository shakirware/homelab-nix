{ config, lib, ... }:

let
  tz = "Europe/London";

  port = 5006;
  bindIp = "0.0.0.0";

  appdataDir = "/srv/appdata/actual";

  gwIp = config.homelab.ips.gw;

  uid = toString config.homelab.ids.uid;
  gid = toString config.homelab.ids.mediaGid;
in {
  systemd.tmpfiles.rules =
    lib.mkAfter [ "d ${appdataDir} 2775 ${config.homelab.ids.user} media - -" ];

  virtualisation.oci-containers.containers.actual = {
    image = "ghcr.io/actualbudget/actual:26.2.0";
    autoStart = true;

    environment = { TZ = tz; };

    extraOptions = [ "--user=${uid}:${gid}" ];

    volumes = [ "${appdataDir}:/data" ];

    ports = [ "${bindIp}:${toString port}:5006" ];
  };

  networking.nftables.tables."actual-backend-guard" = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -50; policy accept;
        tcp dport ${toString port} jump actual_guard
      }

      chain actual_guard {
        ct state established,related accept
        iifname "lo" accept
        ip saddr ${gwIp} accept
        drop
      }
    '';
  };
}
