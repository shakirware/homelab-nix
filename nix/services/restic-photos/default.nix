{ config, lib, pkgs, ... }:

let
  repository = "/srv/diskB/restic-photos";
  photosDir = "/srv/diskA/photos";

  maxAgeSeconds = 26 * 3600;

  textfileDir = "/var/lib/prometheus-node-exporter-textfile";

  passwordFile = config.sops.secrets."restic/repo_password/photos".path;

  restic = "${pkgs.restic}/bin/restic";
  jq = "${pkgs.jq}/bin/jq";

  freshDump = ''
    if [ -z "$(${pkgs.findutils}/bin/find ${photosDir}/backups -maxdepth 1 -name '*.sql.gz' -mmin -${
      toString (maxAgeSeconds / 60)
    } -print -quit 2>/dev/null)" ]; then
      echo "restic-photos: no Immich database dump newer than ${
        toString (maxAgeSeconds / 3600)
      }h in ${photosDir}/backups" >&2
      exit 1
    fi
  '';

  statusMetrics = import ../../modules/backup/metrics.nix { inherit pkgs; } {
    file = "homelab_backup_photos";
    backup = "restic-photos";
    inherit maxAgeSeconds;
  };

  sizeMetrics = pkgs.writeShellScript "restic-photos-size-metrics" ''
    set -euo pipefail
    [ "''${SERVICE_RESULT:-}" = success ] || exit 0
    bytes="$(${restic} -r ${repository} -p ${passwordFile} stats --mode raw-data --json --no-lock | ${jq} .total_size)"
    tmp="$(mktemp "${textfileDir}/.homelab_backup_photos_size.prom.XXXXXX")"
    {
      echo "# HELP homelab_backup_repo_bytes Stored size of a restic repository."
      echo "# TYPE homelab_backup_repo_bytes gauge"
      echo "homelab_backup_repo_bytes{repo=\"local-photos\"} $bytes"
    } > "$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "${textfileDir}/homelab_backup_photos_size.prom"
  '';
in {
  sops.secrets."restic/repo_password/photos".owner = "restic";

  systemd.tmpfiles.rules =
    lib.mkAfter [ "d ${repository} 0700 restic restic - -" ];

  services.restic.backups.photos = {
    user = "restic";
    inherit repository passwordFile;
    initialize = true;

    paths = [ photosDir ];
    extraBackupArgs = [ "--tag" "nightly" ];

    backupPrepareCommand = freshDump;

    pruneOpts = [ "--keep-daily 30" "--keep-monthly 12" ];
    checkOpts = [ "--read-data-subset=2%" ];

    timerConfig = {
      OnCalendar = "03:30";
      Persistent = true;
    };
  };

  systemd.services.restic-backups-photos = {
    unitConfig.RequiresMountsFor = [ "/srv/diskA" "/srv/diskB" ];
    environment.GOMAXPROCS = "2";
    serviceConfig = {
      Nice = 10;
      IOSchedulingClass = "idle";
      AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" ];
      ExecStopPost = [ "+${statusMetrics}" "+${sizeMetrics}" ];
    };
  };

  assertions = [{
    assertion = !(lib.any (p: lib.hasPrefix photosDir p)
      (config.services.restic.backups.storage.paths or [ ]));
    message =
      "${photosDir} must stay out of the storage backup: that repository is copied to B2.";
  }];
}
