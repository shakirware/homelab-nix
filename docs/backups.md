# Backups

Application data is backed up nightly with [restic](https://restic.net): each
VM pushes to an append-only repository on `vm-storage`, and `vm-storage` prunes
the repositories and copies them to Backblaze B2. Media is not backed up; it can
be downloaded again. This guide covers what is protected, how the pieces fit
together, and how to restore.

## Overview

| Time | Where | Unit | What |
| --- | --- | --- | --- |
| 02:30–03:00 | `vm-apps`, `vm-media`, `vm-sensitive` | `restic-backups-local` | Dump databases, then back up to `rest:http://192.168.20.110:8000/<host>/` |
| 04:00 | `vm-storage` | `restic-backups-storage` | Book files and the encrypted Tofu state into `/srv/diskB/restic/vm-storage` |
| ~04:30 | `vm-storage` | `restic-offsite` | Per repository: local `forget --prune`, `copy` to B2, B2 `forget --prune` |
| Sun 06:00 | `vm-storage` | `restic-check` | `check --read-data-subset=5%` on every local and B2 repository |

- **Append-only clients.** The [REST server](../nix/services/restic-server)
  runs with `--append-only --private-repos`: a client can add snapshots to its
  own repository but cannot read another host's or delete anything. Only
  `vm-storage` forgets and prunes.
- **Retention.** 30 daily and 6 monthly snapshots, the same locally and on B2.
- **Off-site.** Bucket `shakir-homelab-restic` (EU), one repository per host,
  each under the same password as its local repository. Caps & Alerts are set to
  $0 and deleted files are kept for 30 days by the bucket lifecycle rule.
- **Encryption.** restic encrypts everything before it leaves the client. The
  repository passwords, REST credentials and B2 key are in sops
  (`secrets/vm-*.yaml`, all copies in `secrets/vm-storage.yaml`).

Services declare what they need under `homelab.backup` in their own module (see
[`nix/modules/backup`](../nix/modules/backup)); a host gets a backup job only
when something is declared. Off-site handling lives in
[`nix/services/restic-offsite`](../nix/services/restic-offsite).

## What is covered

| Host | Data |
| --- | --- |
| `vm-sensitive` | Actual (budget files + SQLite), InvoicePlane (MariaDB + uploads), Standard Notes (MySQL + uploads) |
| `vm-apps` | Kaneo (Postgres), Home Assistant (config, `.storage`, history DB), Obsidian LiveSync (CouchDB), Yamtrack (SQLite) |
| `vm-media` | Sonarr, Radarr, Prowlarr, Bazarr, Jellyfin (users and watch state), Seerr, ReadMeABook (Postgres), Profilarr, Cleanuparr, Tracearr (Postgres), Grimmory (MariaDB), Audiobookshelf, Shelfmark, Pinchflat, qBittorrent |
| `vm-storage` | Book library (from the disk branches), `~/backups` (age-encrypted Tofu state) |

**Not covered:** media files, Prometheus/Loki/Grafana data (Grafana's
provisioned parts are in Nix), Jellyfin metadata and caches, YouTube downloads,
AdGuard logs, and anything defined in this repository.

### Database dumps

Live database files are excluded; consistent dumps are written to
`/srv/backups/dumps` before each run and backed up instead:

| Kind | Method | File |
| --- | --- | --- |
| SQLite | `sqlite3 .backup`, then `PRAGMA quick_check` | `sqlite/<path with / as _>` |
| Postgres | `pg_dump -Fc` inside the container | `postgres/<container>-<db>.dump` |
| MySQL/MariaDB | `--all-databases --single-transaction` with the container's root password | `mysql/<container>.sql` |

## Monitoring

Each run writes node-exporter textfile metrics
(`homelab_backup_last_run_success`, `homelab_backup_last_success_timestamp_seconds`,
`homelab_backup_max_age_seconds`, `homelab_backup_repo_bytes`). Alerts in
[`prometheus`](../nix/services/monitoring/prometheus) fire on a failed run, a
backup older than 26 hours, missing metrics, a failed `restic-check`, and B2
usage above 8 GB. The **Backups** Grafana dashboard shows the same.

## Restoring

### Access

On `vm-storage`, repositories are read directly from disk as the `restic` user,
so file ownership stays correct for the REST server:

```sh
sudo -u restic env RESTIC_PASSWORD_FILE=/run/secrets/restic/repo_password/vm-apps \
  restic -r /srv/diskB/restic/vm-apps snapshots
```

From anywhere else (including a fresh laptop), go to B2 with credentials from
sops:

```sh
export AWS_ACCESS_KEY_ID=$(sops -d --extract '["b2"]["key_id"]' secrets/vm-storage.yaml)
export AWS_SECRET_ACCESS_KEY=$(sops -d --extract '["b2"]["application_key"]' secrets/vm-storage.yaml)
export RESTIC_PASSWORD=$(sops -d --extract '["restic"]["repo_password"]["vm-apps"]' secrets/vm-storage.yaml)
export RESTIC_REPOSITORY=s3:https://s3.eu-central-003.backblazeb2.com/shakir-homelab-restic/vm-apps
restic snapshots
```

### Files

```sh
restic ls latest /srv/appdata/home-assistant/config
restic restore latest --target /tmp/restore --include /srv/appdata/home-assistant/config/automations.yaml
```

Restore into a scratch directory and copy back. To restore in place, stop the
service first (`systemctl stop podman-<name>`) and restore with `--target /`.

### Databases

Restore the dump, then load it into the running database container:

```sh
restic restore latest --target /tmp/restore --include /srv/backups/dumps

# Postgres (stop the app container first, keep the database container running)
podman exec -i kaneo-db dropdb -U kaneo kaneo
podman exec -i kaneo-db createdb -U kaneo kaneo
podman exec -i kaneo-db pg_restore -U kaneo -d kaneo --no-owner \
  < /tmp/restore/srv/backups/dumps/postgres/kaneo-db-kaneo.dump

# MySQL/MariaDB: the dump recreates every database
podman exec -i invoiceplane-db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot' \
  < /tmp/restore/srv/backups/dumps/mysql/invoiceplane-db.sql

# SQLite: replace the live file while the app is stopped
cp /tmp/restore/srv/backups/dumps/sqlite/srv_appdata_yamtrack_db_db.sqlite3 \
  /srv/appdata/yamtrack/db/db.sqlite3
rm -f /srv/appdata/yamtrack/db/db.sqlite3-wal /srv/appdata/yamtrack/db/db.sqlite3-shm
```

ReadMeABook's Postgres runs inside the app container as `postgres`
(`podman exec -u postgres readmeabook …`). The Tracearr dump is TimescaleDB;
restore it with `timescaledb_pre_restore()`/`timescaledb_post_restore()` around
`pg_restore`. Restored files need their original owner: check with `ls -ln`
against the snapshot (`restic ls -l`).

### A whole VM

1. Recreate the VM: `make plan` / `make apply` (OpenTofu), then deploy with
   Colmena. The VM's SSH host key changes, so add its new age key
   (`ssh-to-age`) to `.sops.yaml` and run `sops updatekeys secrets/<vm>.yaml`
   before deploying.
2. Stop the application containers.
3. Restore `/srv/appdata` paths from the latest snapshot with `--target /`,
   then load the database dumps as above.
4. Start the services and check them through Caddy and the Blackbox probes.

### From nothing

If the server and the laptop are both lost, everything comes from the
recovery kit (kept outside the homelab) and B2:

1. On a new machine, install Nix, sops, age and restic; clone this repository.
2. Put the sops admin age key from the recovery kit (public key `age12ad822…`,
   normally `~/.config/mise/age.txt`) somewhere private, point
   `SOPS_AGE_KEY_FILE` at it, and check `sops -d secrets/vm-storage.yaml` works.
   (`~/.config/sops/age/keys.txt` on the laptop holds an unrelated key that is
   not a recipient of anything.)
3. Restore the Tofu state from B2: the `vm-storage` repository contains
   `/home/shakir/backups` with the age-encrypted state files
   (`age -d -i "$SOPS_AGE_KEY_FILE" <file> > terraform.tfstate`): the
   `router-state` and `proxmox-state` directories, written by
   [`backup-state.sh`](../infra/router/backup-state.sh) after each apply.
4. Rebuild Proxmox guests with OpenTofu and deploy with Colmena, updating host
   age keys as in [A whole VM](#a-whole-vm).
5. Restore each VM's data from B2 as above, starting with `vm-sensitive`.

## Restore drill

Restores are tested from **B2**, from the laptop, into scratch containers:

| Date | Restore | Result |
| --- | --- | --- |
| 2026-10-30 | Kaneo Postgres dump → fresh `postgres:16-alpine` | `pg_restore` clean; 13 tasks and both projects present; 31 s including image pull |
| 2026-10-30 | Actual (`/srv/appdata/actual` + SQLite dumps) | All SQLite `integrity_check` ok; every budget file listed in `account.sqlite` has its blob; all blobs are valid archives |

Listing snapshots and restoring both took about 15 seconds. Repeat the drill
quarterly and add a row here.
