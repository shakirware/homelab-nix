{ lib, config, pkgs, ... }:

let
  server = config.homelab.ips.storage;

  export = "/";

  mountPoint = "/srv/media";
  mountUnit = "srv-media.mount";

  # Containers that can see the NFS mount: a volume source at, below or above
  # (e.g. "/srv:/srv:ro") the mount point. Derived from the container
  # definitions so new apps are covered automatically.
  seesMount = v:
    let src = builtins.head (lib.splitString ":" v);
    in src == mountPoint || lib.hasPrefix "${mountPoint}/" src
    || lib.hasPrefix "${src}/" mountPoint;
  mediaContainers = lib.attrNames (lib.filterAttrs
    (_: c: builtins.any seesMount c.volumes)
    config.virtualisation.oci-containers.containers);
in {
  environment.systemPackages = [ pkgs.nfs-utils ];

  systemd.tmpfiles.rules =
    lib.mkAfter [ "d ${mountPoint} 2775 ${config.homelab.ids.user} media - -" ];

  fileSystems.${mountPoint} = {
    device = "${server}:${export}";
    fsType = "nfs4";

    options = [
      "nofail"
      "noatime"
      "_netdev"
      # vm-storage can take minutes to export after an unclean stop (ext4
      # journal replay on the 16 TB disks took ~1m45s on 2026-10-17), so keep
      # retrying instead of failing after 60s. mount.nfs retries for `retry`
      # minutes; systemd must not kill it first.
      "retry=10"
      "x-systemd.mount-timeout=11min"
      "x-systemd.requires=network-online.target"
      "x-systemd.after=network-online.target"
    ];
  };

  # Never start a container against the empty local mount point. mkDefault
  # covers new apps without duplicating a module's own RequiresMountsFor (a
  # changed [Unit] would restart the container on deploy); the assertion below
  # catches a module that sets it without the mount point. WantedBy on the
  # mount means that whenever the mount comes up later, by hand or via the
  # retry timer below, the containers start with it.
  assertions = map (n: {
    assertion = lib.elem mountPoint (lib.toList
      (config.systemd.services."podman-${n}".unitConfig.RequiresMountsFor or [ ]));
    message = "podman-${n} uses ${mountPoint} but does not require it to be mounted";
  }) mediaContainers;

  systemd.services = lib.genAttrs (map (n: "podman-${n}") mediaContainers)
    (_: {
      unitConfig.RequiresMountsFor = lib.mkDefault [ mountPoint ];
      wantedBy = [ mountUnit ];
    }) // {
      media-mount-retry = {
        description = "Retry the NFS media mount if it is not active";
        unitConfig.ConditionPathIsMountPoint = "!${mountPoint}";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.systemd}/bin/systemctl start --no-block ${mountUnit}";
        };
      };
    };

  # Recovers from storage outages longer than the mount's own retry window.
  # OnCalendar rather than OnUnitActiveSec: runs skipped by the condition
  # above would otherwise stop the timer re-arming.
  systemd.timers.media-mount-retry = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*:0/2";
  };
}
