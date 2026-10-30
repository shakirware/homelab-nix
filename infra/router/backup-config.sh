#!/usr/bin/env bash
# Save a RouterOS binary backup (encrypted with ROUTER_BACKUP_PASSWORD) and a
# redacted export, then store both age-encrypted on vm-storage, keeping the
# latest ten of each. Run after every apply.
set -euo pipefail

cd "$(dirname "$0")"
: "${ROUTER_BACKUP_PASSWORD:?set by mise from secrets/env.yaml}"
router=${ROUTER_HOST:-router}
host=${BACKUP_HOST:-vm-storage}
dir=backups/router-config
name="config-$(date +%Y%m%dT%H%M%S)"

args=()
while read -r r; do
  args+=(-r "$r")
done < <(awk '/path_regex: secrets\/env/ {f=1; next} /path_regex/ {f=0} f && /age1/ {print $2}' ../../.sops.yaml)
[ ${#args[@]} -gt 0 ] || { echo "no age recipients found" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"; ssh "$router" "/file remove [find where name~\"^$name\"]" >/dev/null 2>&1 || true' EXIT

# shellcheck disable=SC2029 # name and password are meant to expand locally
ssh "$router" "/system backup save name=$name password=\"$ROUTER_BACKUP_PASSWORD\"; /export file=$name" >/dev/null
sleep 2
scp -q "$router:$name.backup" "$router:$name.rsc" "$tmp/"

for f in "$tmp/$name.backup" "$tmp/$name.rsc"; do
  [ -s "$f" ] || { echo "empty $f" >&2; exit 1; }
  # shellcheck disable=SC2029 # dir and name are meant to expand locally
  ssh "$host" "umask 077; mkdir -p $dir && cat > $dir/$(basename "$f").age" < <(age "${args[@]}" "$f")
  echo "$host:$dir/$(basename "$f").age"
done
# shellcheck disable=SC2029
ssh "$host" "cd $dir && ls -t config-*.backup.age | tail -n +11 | xargs -r rm -f; ls -t config-*.rsc.age | tail -n +11 | xargs -r rm -f"
