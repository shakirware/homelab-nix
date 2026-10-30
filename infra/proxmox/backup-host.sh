#!/usr/bin/env bash
# Archive the Proxmox host's own configuration (/etc/pve, networking, SSH and
# boot settings) age-encrypted to vm-storage, keeping the latest ten. Not
# managed by OpenTofu; run after host changes and every apply.
set -euo pipefail

cd "$(dirname "$0")"
pve=${PVE_HOST:-pve}
host=${BACKUP_HOST:-vm-storage}
dir=backups/proxmox-host
name="pve-$(date +%Y%m%dT%H%M%S).tar.gz.age"

args=()
while read -r r; do
  args+=(-r "$r")
done < <(awk '/path_regex: secrets\/env/ {f=1; next} /path_regex/ {f=0} f && /age1/ {print $2}' ../../.sops.yaml)
[ ${#args[@]} -gt 0 ] || { echo "no age recipients found" >&2; exit 1; }

# shellcheck disable=SC2029 # dir and name are meant to expand locally
ssh "$host" "umask 077; mkdir -p $dir && cat > $dir/$name" < <(
  ssh "$pve" "tar -C / --ignore-failed-read -czf - etc/pve etc/network etc/hosts etc/hostname \
    etc/resolv.conf etc/apt/sources.list.d etc/modprobe.d etc/modules-load.d etc/default/grub \
    etc/kernel etc/vzdump.conf etc/ssh root/.ssh 2>/dev/null" | age "${args[@]}")
# shellcheck disable=SC2029
ssh "$host" "cd $dir && ls -t pve-*.tar.gz.age | tail -n +11 | xargs -r rm -f; ls -l $name" | awk '{print "'"$host:$dir/"'" $NF, $5, "bytes"}'
