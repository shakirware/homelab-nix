#!/usr/bin/env bash
# Copy this stack's OpenTofu state off the laptop, age-encrypted to the
# secrets/env.yaml recipients. infra/proxmox links here; the stack is the
# directory it runs from. Run after every apply. Restore with:
#   age -d -i "$SOPS_AGE_KEY_FILE" <file> > terraform.tfstate
set -euo pipefail

cd "$(dirname "$0")"
stack=$(basename "$PWD")
host=${BACKUP_HOST:-vm-storage}
# Under the remote home; not on an NFS export.
dir=backups/${stack}-state

args=()
while read -r r; do
  args+=(-r "$r")
done < <(awk '/path_regex: secrets\/env/ {f=1; next} /path_regex/ {f=0} f && /age1/ {print $2}' ../../.sops.yaml)
[ ${#args[@]} -gt 0 ] || { echo "no age recipients found" >&2; exit 1; }

serial=$(jq -r .serial terraform.tfstate)
name="terraform-${serial}-$(date +%Y%m%dT%H%M%S).tfstate.age"

# shellcheck disable=SC2029 # dir and name are meant to expand locally
ssh "$host" "umask 077; mkdir -p $dir && cat > $dir/$name" < <(age "${args[@]}" terraform.tfstate)
echo "$host:$dir/$name (serial $serial, $((${#args[@]} / 2)) recipients)"

# Gitignored variables (e.g. the router's SSID and IoT reservations).
for vars in *.private.auto.tfvars; do
  [ -e "$vars" ] || continue
  # shellcheck disable=SC2029
  ssh "$host" "umask 077; cat > $dir/$vars.age" < <(age "${args[@]}" "$vars")
  echo "$host:$dir/$vars.age"
done
