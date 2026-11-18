{ config, lib, ... }:

let

  port = 5006;

  appdataDir = "/srv/appdata/actual";

  gwIp = config.homelab.ips.gw;

  uid = toString config.homelab.ids.uid;
  gid = toString config.homelab.ids.mediaGid;
in {
  systemd.tmpfiles.rules =
    lib.mkAfter [ "d ${appdataDir} 2775 ${config.homelab.ids.user} media - -" ];

  virtualisation.oci-containers.containers.actual = {
    image = "ghcr.io/actualbudget/actual:26.11.0@sha256:06cf186569cf58d93e12659ff1a517b65b5b0ebee7050a3991d4bd8a1d398da6";
    environment = { TZ = config.time.timeZone; };

    extraOptions = [ "--user=${uid}:${gid}" ];

    volumes = [ "${appdataDir}:/data" ];
  };

  homelab.containers.actual.publish.${toString port} = { sources = [ gwIp ]; to = 5006; };

  homelab.backup = {
    paths = [ appdataDir ];
    exclude = [ "${appdataDir}/**/*.sqlite" ];
    sqlite = [
      "${appdataDir}/server-files/*.sqlite"
      "${appdataDir}/user-files/*.sqlite"
    ];
  };
}
