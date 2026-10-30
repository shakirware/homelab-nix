{ config, lib, pkgs, ... }:

# Retention and the Backblaze B2 copy for every restic repository; clients are
# append-only, so only this host prunes.

let
  repoRoot = "/srv/diskB/restic";

  clients = [ "vm-apps" "vm-media" "vm-sensitive" "vm-gw" "vm-monitoring" ];
  repos = clients ++ [ "vm-storage" ];

  # Same policy on both sides, so copy never re-sends snapshots B2 dropped.
  keep = "--group-by host --keep-daily 30 --keep-monthly 6";

  maxAgeSeconds = 26 * 3600;

  stateDir = "/var/lib/restic-offsite";
  textfileDir = "/var/lib/prometheus-node-exporter-textfile";

  envName = "restic-offsite.env";

  passwordFile = repo: config.sops.secrets."restic/repo_password/${repo}".path;

  restic = "${pkgs.restic}/bin/restic";
  jq = "${pkgs.jq}/bin/jq";

  offsite = pkgs.writeShellScript "restic-offsite" ''
    set -uo pipefail

    failed=0
    ${lib.concatMapStrings (repo: ''
      echo "== ${repo}"
      src=${repoRoot}/${repo}
      b2="$B2_REPO_BASE/${repo}"
      pw=${passwordFile repo}
      ok=1
      {
        ${restic} -r "$src" -p "$pw" forget --prune ${keep} &&
        { ${restic} -r "$b2" -p "$pw" cat config >/dev/null 2>&1 ||
          ${restic} -r "$b2" -p "$pw" init --from-repo "$src" \
            --from-password-file "$pw" --copy-chunker-params; } &&
        ${restic} -r "$b2" -p "$pw" copy --from-repo "$src" --from-password-file "$pw" &&
        ${restic} -r "$b2" -p "$pw" forget --prune ${keep}
      } || ok=0

      echo "$ok" > ${stateDir}/${repo}.status
      if [ "$ok" = 1 ]; then
        date +%s > ${stateDir}/${repo}.success
        ${restic} -r "$src" -p "$pw" stats --mode raw-data --json \
          | ${jq} .total_size > ${stateDir}/${repo}.local-bytes || true
        ${restic} -r "$b2" -p "$pw" stats --mode raw-data --json \
          | ${jq} .total_size > ${stateDir}/${repo}.b2-bytes || true
      else
        failed=1
      fi
    '') repos}

    exit "$failed"
  '';

  publish = pkgs.writeShellScript "restic-offsite-metrics" ''
    set -euo pipefail

    tmp="$(mktemp "${textfileDir}/.homelab_backup_offsite.prom.XXXXXX")"
    {
      echo "# HELP homelab_backup_last_run_success Whether the last backup run succeeded."
      echo "# TYPE homelab_backup_last_run_success gauge"
      echo "# HELP homelab_backup_max_age_seconds Age after which the backup is overdue."
      echo "# TYPE homelab_backup_max_age_seconds gauge"
      echo "# HELP homelab_backup_last_success_timestamp_seconds Time of the last successful backup."
      echo "# TYPE homelab_backup_last_success_timestamp_seconds gauge"
      echo "# HELP homelab_backup_repo_bytes Stored size of a restic repository."
      echo "# TYPE homelab_backup_repo_bytes gauge"
      for repo in ${lib.concatStringsSep " " repos}; do
        status="$(cat "${stateDir}/$repo.status" 2>/dev/null || echo 0)"
        echo "homelab_backup_last_run_success{backup=\"offsite-$repo\"} $status"
        echo "homelab_backup_max_age_seconds{backup=\"offsite-$repo\"} ${toString maxAgeSeconds}"
        if [ -s "${stateDir}/$repo.success" ]; then
          echo "homelab_backup_last_success_timestamp_seconds{backup=\"offsite-$repo\"} $(cat "${stateDir}/$repo.success")"
        fi
        for side in local b2; do
          if [ -s "${stateDir}/$repo.$side-bytes" ]; then
            echo "homelab_backup_repo_bytes{repo=\"$side-$repo\"} $(cat "${stateDir}/$repo.$side-bytes")"
          fi
        done
      done
    } > "$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "${textfileDir}/homelab_backup_offsite.prom"
  '';

  storageMetrics = import ../../modules/backup/metrics.nix { inherit pkgs; } {
    file = "homelab_backup_storage";
    backup = "restic-local";
    inherit maxAgeSeconds;
  };

  hardening = {
    Nice = 10;
    IOSchedulingClass = "idle";
  };
in {
  sops.secrets = lib.genAttrs (map (r: "restic/repo_password/${r}") repos)
    (_: { owner = "restic"; }) // {
      "b2/key_id" = { };
      "b2/application_key" = { };
      "b2/bucket" = { };
      "b2/endpoint" = { };
    };

  sops.templates.${envName} = {
    content = ''
      AWS_ACCESS_KEY_ID=${config.sops.placeholder."b2/key_id"}
      AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."b2/application_key"}
      B2_REPO_BASE=s3:https://${config.sops.placeholder."b2/endpoint"}/${
        config.sops.placeholder."b2/bucket"
      }
    '';
    owner = "restic";
    group = "restic";
    mode = "0400";
  };

  # Runs as restic so repository files stay readable by the REST server.
  services.restic.backups.storage = {
    user = "restic";
    repository = "${repoRoot}/vm-storage";
    passwordFile = passwordFile "vm-storage";
    initialize = true;

    # Age-encrypted Tofu state copied here by infra/router/backup-state.sh.
    paths = [ "/home/shakir/backups" ];

    # Books from the disk branches: mergerfs ignores CAP_DAC_READ_SEARCH.
    dynamicFilesFrom = ''
      ls -d /srv/disk*/data/books 2>/dev/null || true
    '';
    extraBackupArgs = [ "--tag" "nightly" ];

    pruneOpts = [ ];

    timerConfig = {
      OnCalendar = "04:00";
      Persistent = true;
    };
  };

  systemd.services.restic-backups-storage = {
    unitConfig.RequiresMountsFor = [ repoRoot "/srv/diskA" "/srv/diskB" ];
    serviceConfig = hardening // {
      AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" ];
      ExecStopPost = [ "+${storageMetrics}" ];
    };
  };

  systemd.services.restic-offsite = {
    description = "Prune restic repositories and copy them to Backblaze B2";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "restic-backups-storage.service" ];
    unitConfig.RequiresMountsFor = [ repoRoot ];
    environment.RESTIC_CACHE_DIR = "/var/cache/restic-offsite";

    serviceConfig = hardening // {
      Type = "oneshot";
      User = "restic";
      Group = "restic";
      EnvironmentFile = config.sops.templates.${envName}.path;
      CacheDirectory = "restic-offsite";
      CacheDirectoryMode = "0700";
      StateDirectory = "restic-offsite";
      StateDirectoryMode = "0700";
      ExecStart = offsite;
      ExecStopPost = [ "+${publish}" ];
    };
  };

  systemd.timers.restic-offsite = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "04:30";
      RandomizedDelaySec = "10m";
      Persistent = true;
    };
  };

  # Weekly read-back of a sample on both sides.
  systemd.services.restic-check = {
    description = "Verify restic repositories locally and on Backblaze B2";
    wants = [ "network-online.target" ];
    after = [ "network-online.target" "restic-offsite.service" ];
    unitConfig.RequiresMountsFor = [ repoRoot ];
    environment.RESTIC_CACHE_DIR = "/var/cache/restic-offsite";

    serviceConfig = hardening // {
      Type = "oneshot";
      User = "restic";
      Group = "restic";
      EnvironmentFile = config.sops.templates.${envName}.path;
      CacheDirectory = "restic-offsite";
      CacheDirectoryMode = "0700";
    };

    script = lib.concatMapStrings (repo: ''
      ${restic} -r ${repoRoot}/${repo} -p ${passwordFile repo} check --read-data-subset=5%
      ${restic} -r "$B2_REPO_BASE/${repo}" -p ${passwordFile repo} check --read-data-subset=5%
    '') repos;
  };

  systemd.timers.restic-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 06:00";
      Persistent = true;
    };
  };
}
