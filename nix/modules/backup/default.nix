{ config, lib, pkgs, ... }:

# Nightly restic backup of this host's app data to the append-only REST
# server on vm-storage (nix/services/restic-server). Service modules declare
# what they need under homelab.backup; the job only exists on hosts where
# something is declared. Retention and the off-site copy run on vm-storage.

let
  cfg = config.homelab.backup;

  host = config.networking.hostName;

  dumpDir = "/srv/backups/dumps";
  # Nightly, so alert once a run is a full day overdue (plus timer jitter).
  maxAgeSeconds = 26 * 3600;

  envName = "restic-backup.env";

  podman = "${pkgs.podman}/bin/podman";

  enabled = cfg.paths != [ ] || cfg.sqlite != [ ] || cfg.postgres != [ ]
    || cfg.mysql != [ ];

  # Live database files are skipped; their dumps in dumpDir are backed up.
  dumpScript = pkgs.writeShellScript "restic-backup-dumps" ''
    set -euo pipefail
    umask 077

    rm -rf ${dumpDir}
    mkdir -p ${dumpDir}/sqlite ${dumpDir}/postgres ${dumpDir}/mysql

    ${lib.concatMapStrings (pattern: ''
      for db in ${pattern}; do
        [ -f "$db" ] || { echo "backup: no SQLite file matches ${pattern}" >&2; exit 1; }
        out="${dumpDir}/sqlite/$(echo "''${db#/}" | tr / _)"
        ${pkgs.sqlite}/bin/sqlite3 "$db" ".timeout 30000" ".backup '$out'"
        ${pkgs.sqlite}/bin/sqlite3 "$out" "PRAGMA quick_check;" | grep -qx ok
      done
    '') cfg.sqlite}

    ${lib.concatMapStrings (p: ''
      ${podman} exec ${lib.optionalString (p.execUser != null) "-u ${p.execUser}"} ${p.container} \
        pg_dump -U ${p.user} -d ${p.db} -Fc \
        > ${dumpDir}/postgres/${p.container}-${p.db}.dump
    '') cfg.postgres}

    ${lib.concatMapStrings (m: ''
      ${podman} exec ${m.container} sh -c \
        'MYSQL_PWD="''${MARIADB_ROOT_PASSWORD:-$MYSQL_ROOT_PASSWORD}" \
          exec "$(command -v mariadb-dump || command -v mysqldump)" -uroot \
          --all-databases --single-transaction --routines --events' \
        > ${dumpDir}/mysql/${m.container}.sql
      tail -n 1 ${dumpDir}/mysql/${m.container}.sql | grep -q "Dump completed"
    '') cfg.mysql}
  '';

  metricsScript = import ./metrics.nix { inherit pkgs; } {
    file = "homelab_backup";
    backup = "restic-local";
    inherit maxAgeSeconds;
  };
in {
  options.homelab.backup = {
    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths to back up.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "restic exclude patterns.";
    };

    sqlite = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description =
        "SQLite files (shell globs) copied with .backup before each run. Exclude the live files from paths.";
    };

    postgres = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          container = lib.mkOption { type = lib.types.str; };
          db = lib.mkOption { type = lib.types.str; };
          user = lib.mkOption { type = lib.types.str; };
          execUser = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "User to run pg_dump as inside the container.";
          };
        };
      });
      default = [ ];
      description = "Postgres databases dumped with pg_dump -Fc.";
    };

    mysql = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options.container = lib.mkOption { type = lib.types.str; };
      });
      default = [ ];
      description =
        "MySQL/MariaDB containers dumped in full with the root password from their environment.";
    };
  };

  config = lib.mkIf enabled {
    sops.secrets."restic/repo_password" = { };
    sops.secrets."restic/rest_password" = { };

    sops.templates.${envName} = {
      content = ''
        RESTIC_REST_USERNAME=${host}
        RESTIC_REST_PASSWORD=${config.sops.placeholder."restic/rest_password"}
      '';
      owner = "root";
      group = "root";
      mode = "0400";
    };

    systemd.tmpfiles.rules = lib.mkAfter [ "d /srv/backups 0700 root root - -" ];

    services.restic.backups.local = {
      repository = "rest:https://${config.homelab.ips.storage}:8000/${host}/";
      passwordFile = config.sops.secrets."restic/repo_password".path;
      environmentFile = config.sops.templates.${envName}.path;
      initialize = true;

      paths = cfg.paths ++ [ dumpDir ];
      exclude = cfg.exclude ++ [ "*.db-wal" "*.db-shm" "*.sqlite-wal" "*.sqlite-shm" ];
      extraBackupArgs = [ "--tag" "nightly" "--exclude-caches" ];

      backupPrepareCommand = toString dumpScript;
      backupCleanupCommand = toString metricsScript;

      # Append-only server: forget/prune happen on vm-storage.
      pruneOpts = [ ];

      timerConfig = {
        OnCalendar = "02:30";
        RandomizedDelaySec = "30m";
        Persistent = true;
      };
    };

    # The REST server's private certificate (nix/services/restic-server).
    systemd.services.restic-backups-local.environment.RESTIC_CACERT =
      "${../../services/restic-server/tls.crt}";

    systemd.services.restic-backups-local.serviceConfig = {
      Nice = 10;
      IOSchedulingClass = "idle";
    };
  };
}
