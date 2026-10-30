{ config, lib, ... }:

let
  tz = "Europe/London";

  uid = toString config.homelab.ids.uid;
  gid = toString config.homelab.ids.mediaGid;

  bindIp = "0.0.0.0";
  port = 8945;

  appdataDir = "/srv/appdata/pinchflat";

  # Where Pinchflat should put YouTube downloads.
  # This will be visible in Jellyfin under /srv/media/youtube.
  downloadsDir = "/srv/media/youtube";

  gwIp = config.homelab.ips.gw;
in {
  # downloadsDir lives on the NFS mount and is created by media-library-dirs
  # on vm-storage. tmpfiles runs before the mount at boot, so rules for it
  # would write to the local mount point instead.
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${appdataDir} 2775 ${config.homelab.ids.user} media - -"
    "Z ${appdataDir} - ${config.homelab.ids.user} media - -"
  ];

  virtualisation.oci-containers.containers.pinchflat = {
    image = "ghcr.io/kieraneglin/pinchflat:latest@sha256:01b4f98aabaf3f5fe394213f7a32578c9e84e42080f52e2f8334021a4473b202";
    autoStart = true;

    environment = {
      TZ = tz;
      UMASK = "002";
    };

    volumes = [
      "${appdataDir}:/config"
      "${downloadsDir}:/downloads"
    ];

    ports = [ "${bindIp}:${toString port}:${toString port}" ];

    extraOptions = [
      "--name=pinchflat"
      "--user=${uid}:${gid}"
    ];
  };

  systemd.services.podman-pinchflat = {
    after = [ "network-online.target" "srv-media.mount" "podman.service" ];
    requires = [ "srv-media.mount" "podman.service" ];
    wants = [ "network-online.target" ];
    unitConfig.RequiresMountsFor = [ "/srv/media" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  # Hooked before dstnat: Podman DNATs the published port, so the packet is
  # forwarded to the container and never reaches the input hook.
  networking.nftables.tables."pinchflat-backend-guard" = {
    family = "inet";
    content = ''
      chain prerouting {
        type filter hook prerouting priority -150; policy accept;
        fib daddr type local tcp dport ${toString port} jump pinchflat_guard
      }

      chain pinchflat_guard {
        ct state established,related accept
        iifname "lo" accept
        ip saddr ${gwIp} accept
        drop
      }
    '';
  };

  # Downloads can be fetched again; keep the database and settings.
  homelab.backup = {
    paths = [ appdataDir ];
    exclude = [ "${appdataDir}/db" "${appdataDir}/logs" ];
    sqlite = [ "${appdataDir}/db/pinchflat.db" ];
  };
}
