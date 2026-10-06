{ config, lib, pkgs, ... }:

let
  mediaRoot = "/srv/media";
  textfileDir = "/var/lib/prometheus-node-exporter-textfile";

  # Every container volume whose host source lives on the NFS media mount,
  # derived from the container definitions so new apps are covered
  # automatically. A host-side check alone is not enough: stale handles only
  # showed up inside the containers' bind mounts.
  mediaVolumes = lib.concatLists (lib.mapAttrsToList (name: c:
    lib.concatMap (v:
      let parts = lib.splitString ":" v;
      in lib.optional (builtins.length parts >= 2 && (builtins.head parts
        == mediaRoot || lib.hasPrefix "${mediaRoot}/" (builtins.head parts))) {
          container = name;
          source = builtins.head parts;
          dest = builtins.elemAt parts 1;
        }) c.volumes) config.virtualisation.oci-containers.containers);

  hostPaths = lib.unique ([ mediaRoot ] ++ map (v: v.source) mediaVolumes);

  probe = pkgs.writeShellApplication {
    name = "homelab-mount-probe";
    runtimeInputs = with pkgs; [ coreutils findutils util-linux podman ];
    text = ''
      out="${textfileDir}/homelab_mount.prom"
      tmp="$(mktemp "${textfileDir}/.homelab_mount.XXXXXX")"
      trap 'rm -f "$tmp"' EXIT

      # stat the filesystem and read one directory entry, so stale handles,
      # I/O errors and missing paths all fail. Never prints entry names.
      check() {
        timeout -k 2 10 stat -f -- "$1" >/dev/null 2>&1 &&
          timeout -k 2 10 find "$1" -mindepth 1 -maxdepth 1 -print -quit \
            >/dev/null 2>&1
      }

      {
        echo "# HELP homelab_mount_nfs_mounted Whether the path is an active NFS mount."
        echo "# TYPE homelab_mount_nfs_mounted gauge"
        if findmnt -rn -t nfs,nfs4 -M "${mediaRoot}" >/dev/null; then m=1; else m=0; fi
        echo "homelab_mount_nfs_mounted{path=\"${mediaRoot}\"} $m"

        echo "# HELP homelab_mount_path_healthy Whether the path can be stat'ed and listed."
        echo "# TYPE homelab_mount_path_healthy gauge"
        ${lib.concatMapStrings (p: ''
          if check "${p}"; then h=1; else h=0; fi
          echo "homelab_mount_path_healthy{scope=\"host\",container=\"\",path=\"${p}\"} $h"
        '') hostPaths}
        echo "# HELP homelab_mount_probe_container_running Whether the container was running when probed."
        echo "# TYPE homelab_mount_probe_container_running gauge"
        ${lib.concatMapStrings (v: ''
          pid="$(podman inspect --format '{{.State.Pid}}' "${v.container}" 2>/dev/null || echo 0)"
          if [ "''${pid:-0}" -gt 0 ]; then
            echo "homelab_mount_probe_container_running{container=\"${v.container}\",path=\"${v.dest}\"} 1"
            if check "/proc/$pid/root${v.dest}"; then h=1; else h=0; fi
            echo "homelab_mount_path_healthy{scope=\"container\",container=\"${v.container}\",path=\"${v.dest}\"} $h"
          else
            echo "homelab_mount_probe_container_running{container=\"${v.container}\",path=\"${v.dest}\"} 0"
          fi
        '') mediaVolumes}
        echo "# HELP homelab_mount_probe_last_run_timestamp_seconds Completion time of the last probe run."
        echo "# TYPE homelab_mount_probe_last_run_timestamp_seconds gauge"
        echo "homelab_mount_probe_last_run_timestamp_seconds $(date +%s)"
      } >"$tmp"

      chmod 0644 "$tmp"
      mv -f "$tmp" "$out"
    '';
  };
in {
  systemd.tmpfiles.rules = lib.mkAfter [ "d ${textfileDir} 0755 root root - -" ];

  services.prometheus.exporters.node.extraFlags =
    [ "--collector.textfile.directory=${textfileDir}" ];

  systemd.services.homelab-mount-probe = {
    description = "Probe NFS media paths on the host and inside containers";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe probe;
      # A hung hard NFS mount must not wedge the unit forever; the alert on
      # the last-run timestamp catches that case.
      TimeoutStartSec = "50s";
    };
  };

  systemd.timers.homelab-mount-probe = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "1min";
      AccuracySec = "5s";
    };
  };
}
