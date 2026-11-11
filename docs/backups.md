# Backups

## Overview

Selected application data and database dumps are backed up with [Restic](https://restic.net/):

```text
vm-gw / vm-apps / vm-media / vm-sensitive / vm-monitoring
    └── nightly encrypted Restic snapshots
        └── vm-storage (private, append-only REST repositories)
            └── retention and scheduled copy to Backblaze B2

vm-storage ── local Restic snapshot ──┘

diskA:/srv/diskA/photos (Immich) ── nightly ──> diskB:/srv/diskB/restic-photos (local only, never copied to B2)
```

Each VM has its own repository. The REST server accepts backups only from the configured clients; clients cannot delete snapshots. `vm-storage` handles retention and off-site replication. Repository passwords and B2 credentials are managed with sops-nix.

The Nix configuration defines this pipeline; successful scheduled runs and actual restore readiness must be checked on the running hosts.

## Backup coverage

| Host | Selected data |
| --- | --- |
| `vm-gw` | AdGuard Home configuration |
| `vm-apps` | Home Assistant configuration/data, Obsidian Livesync data, Yamtrack SQLite, Mealie SQLite and recipe images, Kaneo PostgreSQL and the Immich PostgreSQL database (uncompressed `pg_dump -Fc -Z0`, so nightly dumps deduplicate) |
| `vm-media` | Jellyfin and media-app configurations/databases (including *arr services and the Profilarr v2 SQLite database, which holds its profiles, custom formats and sync settings), Audiobookshelf, qBittorrent settings and other declared app data |
| `vm-sensitive` | Actual Budget, Standard Notes, InvoicePlane and Vaultwarden data/databases |
| `vm-monitoring` | Grafana SQLite database |
| `vm-storage` | Books from available disk branches and locally stored, age-encrypted infrastructure backups |
| `vm-storage` (photos repository) | Immich originals, profile images and Immich's own daily database dumps from `/srv/diskA/photos`; **local only** |

SQLite databases are copied using SQLite's `.backup` command and checked before each snapshot. PostgreSQL uses `pg_dump`; MariaDB/MySQL uses logical SQL dumps. These dumps are stored under `/srv/backups/dumps` in the client snapshots. The backup module excludes common SQLite WAL/SHM files, and services declare further exclusions for caches, logs and live databases. Client backups use `--compression max`, as their data is small and mostly text.

Only paths and databases declared through `homelab.backup` are included. The [service modules](../nix/services/) are the source of truth for individual files and exclusions; the shared implementation is in [`nix/modules/backup/default.nix`](../nix/modules/backup/default.nix).

## Schedule and retention

Times are host-local (`Europe/London`). `Persistent=true` means missed timer events are triggered when the host becomes available again.

| Job | Schedule |
| --- | --- |
| Immich's own database dump (to `/srv/diskA/photos/backups`) | Daily at 02:00 |
| Client backups (`vm-gw`, `vm-apps`, `vm-media`, `vm-sensitive`, `vm-monitoring`) | Daily at 02:30, randomized by up to 30 minutes |
| Immich photos (`restic-backups-photos`) | Daily at 03:30 |
| `vm-storage` local backup | Daily at 04:00 |
| Local retention and B2 replication | Daily at 04:30, randomized by up to 10 minutes |
| Local and B2 repository integrity checks | Sundays at 06:00 |

| Repositories | Retention | Integrity check |
| --- | --- | --- |
| Client and `vm-storage` repositories, locally and on B2 | **30 daily + 6 monthly**, grouped by host | Weekly, reading a 5% data sample on each side |
| Photos repository (local only) | **30 daily + 12 monthly**, so a deleted photo stays recoverable for about a year | Daily after each backup, reading a 2% data sample |

Retention, copying and the weekly checks are defined in [`nix/services/restic-offsite/default.nix`](../nix/services/restic-offsite/default.nix). The append-only server is defined in [`nix/services/restic-server/default.nix`](../nix/services/restic-server/default.nix).

## Immich photos

Immich keeps originals on `diskA` (`/srv/diskA/photos`, outside the mergerfs pool) and its PostgreSQL database, thumbnails and transcoded video on `vm-apps`. Thumbnails and transcoded video are regenerable and not backed up.

- **Photos repository:** `/srv/diskB/restic-photos` on `vm-storage`, defined in [`restic-photos/default.nix`](../nix/services/restic-photos/default.nix). It is outside the REST server's data directory and outside `restic-offsite`'s repository list, and an assertion stops `/srv/diskA/photos` being added to the B2-replicated `storage` job. It has its own password and uses `auto` compression, since photos and video are already compressed.
- **One unit, in order:** the job first requires an Immich database dump newer than 26 hours in `/srv/diskA/photos/backups`, so every snapshot holds a dump taken before its files. It then backs up, applies retention and runs the integrity check. Any failure stops the chain and raises `BackupLastRunFailed{backup="restic-photos"}`.
- **Database off-site:** the Immich database is also dumped by `vm-apps`' nightly job, so it reaches B2 with the other client repositories.

> **Photos have no off-site copy.** Originals are on `diskA` and their only backup is on `diskB` in the same machine. Fire, theft, a power or controller fault that damages both drives, or an attacker with root on `vm-storage` (this repository is not append-only) can destroy both. This protects against a single disk failure and accidental deletion, not against losing the host.

## Verification

- **Restore drill (2026-11-08, disposable sample data):** a full restore of the photos repository matched production by checksum. The Immich database dump was restored from B2 into an isolated Immich instance; with a representative subset of the originals, its assets, albums and metadata matched production.
- **Google Takeout import (2026-11-08):** 6,900 assets were imported. The local photos snapshot taken afterwards contains every file on `/srv/diskA/photos`, matched by file count, and its integrity check passed. The full imported library has **not** been restore-tested.
- **Ongoing:** scheduled integrity checks validate repository data, not whether every service can be fully recovered.

## Monitoring

Every job writes its last result, last success time and expected maximum age to Node Exporter's textfile collector; repository sizes are reported locally, on B2 and for the photos repository. The Grafana **Backups** dashboard shows these, and Prometheus alerts on:
- failed or overdue backups;
- failed integrity checks;
- missing backup metrics;
- B2 usage nearing the free tier.

## Limitations

- **No full-VM backups:** Proxmox VM images/disks and automated whole-host recovery are outside this Restic setup. Separately saved Proxmox host configuration is not a VM image.
- **Selective coverage:** Bulk media, downloads, most caches/logs, and Prometheus/Loki history are not included; books are backed up separately from `vm-storage`.
- **No disk redundancy:** mergerfs pools drives without parity or mirroring. Local repositories on `vm-storage` share the same physical host and can be lost with it.
- **No off-site photos:** Immich originals are protected by the local photos repository only (see above).
- **Restore verification:** Periodic end-to-end restore tests remain necessary.
- **Operational status:** Nix configuration proves the jobs are defined, not that they have run successfully or that the off-site copy is complete; the dashboard and alerts show the actual state.
