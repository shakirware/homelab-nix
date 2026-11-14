{ config, lib, home, ... }:

let

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
  virtualisation.oci-containers.containers.netv = {
    image = "ghcr.io/jvdillon/netv:0.4.3@sha256:2e700fd2da35fbc7b52e2f0dd667498b6bf7b9d773dae33f95484ece4249cb25";
    environment = {
      TZ = config.time.timeZone;
      NETV_PORT = toString port;
    };

    volumes = [
      "${cacheDir}:/app/cache"
      "/etc/localtime:/etc/localtime:ro"
    ];

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

  homelab.containers.netv = {
    publish.${toString port} = [ gwIp home.cidr ];
    # Created owned by the host admin like every other /srv/appdata service:
    # tmpfiles refuses to descend into a directory whose owner differs from its
    # parent.  The upstream entrypoint chowns the cache to its own `netv` user
    # (uid 10001) on first start, which is the case it is written to handle.
    appdata = [
      appdataDir
      cacheDir
    ];
  };
}
