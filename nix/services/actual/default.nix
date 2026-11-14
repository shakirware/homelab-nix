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
    image = "ghcr.io/actualbudget/actual:26.10.0@sha256:24645e971da6bb1a1f953d6859e307a0b29be1e8b4130a35b3220c209b5b860c";
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
