# Backups

## Overview

Selected application data and database dumps are backed up with [Restic](https://restic.net/):

```text
vm-gw / vm-apps / vm-media / vm-sensitive / vm-monitoring
    └── nightly encrypted Restic snapshots
        └── vm-storage (private, append-only REST repositories)
            └── retention and scheduled copy to Backblaze B2

vm-storage ── local Restic snapshot ──┘
```

Each VM has its own repository. The REST server accepts backups only from the configured clients; clients cannot delete snapshots. `vm-storage` handles retention and off-site replication. Repository passwords and B2 credentials are managed with sops-nix.

The Nix configuration defines this pipeline; successful scheduled runs and actual restore readiness must be checked on the running hosts.

## Backup coverage

| Host | Selected data |
| --- | --- |
| `vm-gw` | AdGuard Home configuration |
| `vm-apps` | Home Assistant configuration/data, Obsidian Livesync data, Yamtrack SQLite and Kaneo PostgreSQL |
| `vm-media` | Jellyfin and media-app configurations/databases (including *arr services), Audiobookshelf, qBittorrent settings and other declared app data |
| `vm-sensitive` | Actual Budget, Standard Notes, InvoicePlane and Vaultwarden data/databases |
| `vm-monitoring` | Grafana SQLite database |
| `vm-storage` | Books from available disk branches and locally stored, age-encrypted infrastructure backups |

SQLite databases are copied using SQLite's `.backup` command and checked before each snapshot. PostgreSQL uses `pg_dump`; MariaDB/MySQL uses logical SQL dumps. These dumps are stored under `/srv/backups/dumps` in the client snapshots. The backup module excludes common SQLite WAL/SHM files, and services declare further exclusions for caches, logs and live databases.

Only paths and databases declared through `homelab.backup` are included. The [service modules](../nix/services/) are the source of truth for individual files and exclusions; the shared implementation is in [`nix/modules/backup/default.nix`](../nix/modules/backup/default.nix).

## Schedule and retention

Times are host-local (`Europe/London`). `Persistent=true` means missed timer events are triggered when the host becomes available again.

| Job | Schedule |
| --- | --- |
| Client backups (`vm-gw`, `vm-apps`, `vm-media`, `vm-sensitive`, `vm-monitoring`) | Daily at 02:30, randomized by up to 30 minutes |
| `vm-storage` local backup | Daily at 04:00 |
| Local retention and B2 replication | Daily at 04:30, randomized by up to 10 minutes |
| Local and B2 repository integrity checks | Sundays at 06:00 |

Local and B2 repositories use the same retention policy: **30 daily and 6 monthly snapshots**, grouped by host. The weekly `restic check` reads a **5% data sample** from each repository on both sides; it is not a full restore test.

Retention, copying and checks are defined in [`nix/services/restic-offsite/default.nix`](../nix/services/restic-offsite/default.nix). The append-only server is defined in [`nix/services/restic-server/default.nix`](../nix/services/restic-server/default.nix).

## Monitoring and recovery

The Grafana **Backups** dashboard shows last-success age, job status and repository sizes. Prometheus alerts on failed/overdue backups, failed integrity checks, missing backup metrics and B2 usage approaching the configured threshold.

Check timers and recent logs on a client VM:

```bash
systemctl list-timers --all 'restic*'
systemctl status restic-backups-local.service
journalctl -u restic-backups-local.service -n 100 --no-pager
```

On `vm-storage`, inspect the storage backup, off-site copy and integrity-check jobs:

```bash
systemctl list-timers --all 'restic*'
systemctl status restic-backups-storage.service restic-offsite.service restic-check.service
journalctl -u restic-offsite.service -n 100 --no-pager
journalctl -u restic-check.service -n 100 --no-pager
```

**Restoring files:** first restore into a temporary directory, not over a running service. For example, on `vm-storage`, inspect the `vm-gw` snapshots and stage its AdGuard configuration (with the `restic` CLI available on `PATH`):

```bash
RESTIC="$(command -v restic)"
sudo -u restic "$RESTIC" \
  -r /srv/diskB/restic/vm-gw \
  -p /run/secrets/restic/repo_password/vm-gw snapshots

sudo -u restic "$RESTIC" \
  -r /srv/diskB/restic/vm-gw \
  -p /run/secrets/restic/repo_password/vm-gw \
  restore latest --target /var/tmp/restic-restore \
  --include '/var/lib/private/AdGuardHome/AdGuardHome.yaml'
```

Inspect the staged files, then transfer only what is needed to the target VM. Stop the affected service where necessary, restore correct ownership/permissions, restart it and verify functionality. For database recovery, restore the staged dump with the appropriate SQLite, `pg_restore` or MariaDB procedure rather than copying a live database blindly.

If `vm-storage` is lost, recover the repository from B2 using its credentials and the corresponding Restic repository password, then follow the same staging-and-validation approach. Keep access to the SOPS/age recovery keys independent of the failed machine.

## Limitations

- **No full-VM backups:** Proxmox VM images/disks and automated whole-host recovery are outside this Restic setup. Separately saved Proxmox host configuration is not a VM image.
- **Selective coverage:** Bulk media, downloads, most caches/logs, and Prometheus/Loki history are not included; books are backed up separately from `vm-storage`.
- **No disk redundancy:** mergerfs pools drives without parity or mirroring. Local repositories on `vm-storage` share the same physical host and can be lost with it.
- **Restore verification:** Scheduled checks validate repository data, not whether every service can be fully recovered. Periodic end-to-end restore tests remain necessary.
- **Operational status:** Nix configuration proves the jobs are defined, not that they have run successfully or that the off-site copy is complete. Confirm this from the dashboard and service logs.
