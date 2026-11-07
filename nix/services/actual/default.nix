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
    image = "ghcr.io/actualbudget/actual:26.11.0@sha256:06cf186569cf58d93e12659ff1a517b65b5b0ebee7050a3991d4bd8a1d398da6";
    autoStart = true;

    environment = { TZ = tz; };

    extraOptions = [ "--user=${uid}:${gid}" ];

    volumes = [ "${appdataDir}:/data" ];

    ports = [ "${bindIp}:${toString port}:5006" ];
  };

  # Before dstnat: Podman's DNAT bypasses the input hook.
  networking.nftables.tables."actual-backend-guard" = {
    family = "inet";
    content = ''
      chain prerouting {
        type filter hook prerouting priority -150; policy accept;
        fib daddr type local tcp dport ${toString port} jump actual_guard
      }

      chain actual_guard {
        ct state established,related accept
        iifname "lo" accept
        ip saddr ${gwIp} accept
        drop
      }
    '';
  };

  homelab.backup = {
    paths = [ appdataDir ];
    exclude = [ "${appdataDir}/**/*.sqlite" ];
    sqlite = [
      "${appdataDir}/server-files/*.sqlite"
      "${appdataDir}/user-files/*.sqlite"
    ];
  };
}
