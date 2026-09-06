{ config, lib, home, ... }:

let
  tz = "Europe/London";

  bindIp = "0.0.0.0";
  port = 8000;

  appdataDir = "/srv/appdata/netv";
  cacheDir = "${appdataDir}/cache";

  # The Intel UHD 630 passed through to this VM is card1 + renderD128
  # (i915, 8086:3e91).  card0 is the Bochs virtual display and is of no use
  # for transcoding, so only the render node is exposed here.  The upstream
  # entrypoint stats exactly this path to discover the host render GID.
  renderDevice = "/dev/dri/renderD128";

  gwIp = config.homelab.ips.gw;
in {
  # Created owned by the host admin like every other /srv/appdata service:
  # tmpfiles refuses to descend into a directory whose owner differs from its
  # parent.  The upstream entrypoint chowns the cache to its own `netv` user
  # (uid 10001) on first start, which is the case it is written to handle.
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${appdataDir} 2775 ${config.homelab.ids.user} media - -"
    "d ${cacheDir} 2775 ${config.homelab.ids.user} media - -"
  ];

  virtualisation.oci-containers.containers.netv = {
    image = "ghcr.io/jvdillon/netv:latest@sha256:40d07f67b0bda1e29430bbead1fdc7adcfe6415cc73ebe948eb345f2ec09738d";
    autoStart = true;

    environment = {
      TZ = tz;
      NETV_PORT = toString port;
    };

    volumes = [
      "${cacheDir}:/app/cache"
      "/etc/localtime:/etc/localtime:ro"
    ];

    ports = [ "${bindIp}:${toString port}:${toString port}" ];

    # No --user override: the entrypoint must start privileged so it can chown
    # the cache and add netv to the host render group before gosu drops it.
    #
    # The image is published in OCI format, which has no Config.Healthcheck
    # field, so the upstream HEALTHCHECK survives only in the image history and
    # podman registers nothing.  These flags restore that same probe -- GET /
    # following redirects until 200 -- with upstream's own timings.  As with a
    # Docker HEALTHCHECK, an unhealthy result is reported, not acted on;
    # systemd's Restart=always still covers an outright crash.
    extraOptions = [
      "--device=${renderDevice}:${renderDevice}"
      "--health-cmd=curl -fsSL -o /dev/null http://localhost:${toString port}/"
      "--health-interval=30s"
      "--health-timeout=10s"
      "--health-start-period=10s"
      "--health-retries=3"
    ];
  };

  systemd.services.podman-netv = {
    after = [ "network-online.target" "podman.service" ];
    requires = [ "podman.service" ];
    wants = [ "network-online.target" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  # Published container ports are DNATed by netavark at nat-prerouting, so the
  # packet is forwarded to the container rather than delivered locally and an
  # input-hook filter never sees it.  The forward chain matches the original
  # pre-DNAT destination port via conntrack, which is what actually gates
  # access here; the input chain covers any non-DNATed path to the same port.
  networking.nftables.tables."netv-backend-guard" = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -50; policy accept;
        tcp dport ${toString port} jump netv_guard
      }

      chain forward {
        type filter hook forward priority -50; policy accept;
        ct status dnat ct original proto-dst ${toString port} jump netv_guard
      }

      chain netv_guard {
        ct state established,related accept
        iifname "lo" accept
        iifname "tailscale0" accept
        ip saddr ${gwIp} accept
        ip saddr ${home.cidr} accept
        drop
      }
    '';
  };
}
