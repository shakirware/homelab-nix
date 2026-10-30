{ pkgs }:

# ExecStopPost script writing the backup metrics the Prometheus alerts read.
# Needs root ("+" prefix in services running as another user).
{ file, backup, maxAgeSeconds }:

let textfileDir = "/var/lib/prometheus-node-exporter-textfile";
in pkgs.writeShellScript "${file}-metrics" ''
  set -euo pipefail

  write() {
    tmp="$(mktemp "${textfileDir}/.$1.XXXXXX")"
    cat > "$tmp"
    chmod 0644 "$tmp"
    mv -f "$tmp" "${textfileDir}/$1"
  }

  ok=0
  [ "''${SERVICE_RESULT:-}" = success ] && ok=1

  write ${file}_status.prom <<EOF
  # HELP homelab_backup_last_run_success Whether the last backup run succeeded.
  # TYPE homelab_backup_last_run_success gauge
  homelab_backup_last_run_success{backup="${backup}"} $ok
  # HELP homelab_backup_max_age_seconds Age after which the backup is overdue.
  # TYPE homelab_backup_max_age_seconds gauge
  homelab_backup_max_age_seconds{backup="${backup}"} ${toString maxAgeSeconds}
  EOF

  if [ "$ok" = 1 ]; then
    write ${file}_success.prom <<EOF
  # HELP homelab_backup_last_success_timestamp_seconds Time of the last successful backup.
  # TYPE homelab_backup_last_success_timestamp_seconds gauge
  homelab_backup_last_success_timestamp_seconds{backup="${backup}"} $(date +%s)
  EOF
  fi
''
