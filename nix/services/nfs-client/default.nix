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

  # "container dest" pairs for those volumes, for the stale-handle check.
  mediaBinds = lib.concatLists (lib.mapAttrsToList (name: c:
    map (v: "${name} ${builtins.elemAt (lib.splitString ":" v) 1}")
    (builtins.filter seesMount c.volumes))
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

      # The export is a mergerfs (FUSE) pool, so restarting mergerfs or NFS on
      # vm-storage can leave handles stale: on the host mount (seen after its
      # 26.05 reboot) or only inside containers' bind mounts of subdirectories
      # (seen after an nfs-server restart, while the host mount was fine).
      # A stale host mount is remounted, which also restarts the containers
      # that require it; a stale bind restarts just that container. Only
      # ESTALE triggers this: a hung stat means the server is down, and a
      # remount would not help.
      media-mount-stale = {
        description = "Recover the NFS media mount and container binds from stale handles";
        path = [ pkgs.coreutils pkgs.findutils pkgs.gnugrep pkgs.systemd pkgs.podman ];
        serviceConfig.Type = "oneshot";
        # /proc/self/mounts, not findmnt/mountpoint: those stat the path and
        # fail on the very ESTALE this is looking for. stale() reads one entry
        # because a stale bind can still answer stat from cache.
        script = ''
          stale() {
            out=$(timeout 10 find "$1" -mindepth 1 -maxdepth 1 -print -quit 2>&1 >/dev/null) && return 1
            case "$out" in *"Stale file handle"*) return 0 ;; esac
            return 1
          }

          grep -q " ${mountPoint} nfs4 " /proc/self/mounts || exit 0
          if stale ${mountPoint}; then
            echo "stale NFS handle on ${mountPoint}; restarting ${mountUnit}"
            systemctl restart ${mountUnit}
            exit 0
          fi

          restarted=" "
          while read -r c dest; do
            case "$restarted" in *" $c "*) continue ;; esac
            pid=$(podman inspect --format '{{.State.Pid}}' "$c" 2>/dev/null || echo 0)
            [ "''${pid:-0}" -gt 0 ] || continue
            if stale "/proc/$pid/root$dest"; then
              echo "stale NFS handle on $dest in $c; restarting podman-$c"
              systemctl restart "podman-$c.service"
              restarted="$restarted$c "
            fi
          done <<'EOF'
          ${lib.concatStringsSep "\n" mediaBinds}
          EOF
        '';
      };
    };

  systemd.timers.media-mount-stale = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*:1/2";
  };

  # Recovers from storage outages longer than the mount's own retry window.
  # OnCalendar rather than OnUnitActiveSec: runs skipped by the condition
  # above would otherwise stop the timer re-arming.
  systemd.timers.media-mount-retry = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*:0/2";
  };
}
