#!/usr/bin/env bash
# Summarise the router's firewall observations (FW-OBS-* / FW-DROP-*) from
# Loki: every distinct unmatched flow with its count, busiest first. Source
# ports are ignored so repeated connections collapse into one row.
#
#   infra/router/review-observations.sh            # last 48 hours
#   infra/router/review-observations.sh 72         # last 72 hours
#   PREFIX=FW-DROP infra/router/review-observations.sh 24   # after enforcement
#
# Each row is either a legitimate flow that needs an accept rule in
# firewall.tf before enforcement, or traffic the final deny should drop.
set -euo pipefail

hours="${1:-48}"
prefix="${PREFIX:-FW-OBS}"
loki_host="${LOKI_HOST:-vm-monitoring}"

# RouterOS line: "<prefix> <chain>: in:<if> out:<if>, connection-state:new
# src-mac <mac>, proto <proto>, <src>:<sport>-><dst>:<dport>, len <n>"
pattern='<_> <chain>: in:<in> out:<out>, connection-state:<_> src-mac <_>, proto <proto>, <src>:<_>-><dst>:<dport>, len <_>'
query="sum by (chain, in, out, proto, src, dst, dport) (count_over_time({job=\"router-syslog\"} |= \"${prefix}-\" | pattern \`${pattern}\` [${hours}h]))"

# ICMP and other port-less lines do not fit the pattern; count them apart.
query_other="sum(count_over_time({job=\"router-syslog\"} |= \"${prefix}-\" !~ \"->[0-9.]+:[0-9]+,\" [${hours}h]))"

loki() {
  # shellcheck disable=SC2029 # the query is expanded locally on purpose
  ssh "$loki_host" "curl -fsSG http://127.0.0.1:3100/loki/api/v1/query --data-urlencode $(printf %q "query=$1")"
}

echo "Unmatched flows, last ${hours}h (${prefix}-*), busiest first:"
printf '%7s  %-7s %-9s %-9s %-10s %-16s %-16s %s\n' count chain in out proto src dst port
loki "$query" | jq -r '
  .data.result
  | map(select(.metric.dport != null and .metric.dport != ""))
  | sort_by(-(.value[1] | tonumber))[]
  | [.value[1], .metric.chain, .metric.in, .metric.out, .metric.proto, .metric.src, .metric.dst, .metric.dport]
  | @tsv' |
  while IFS=$'\t' read -r count chain in out proto src dst dport; do
    [ "$out" = "(unknown 0)" ] && out=router # input chain: the router itself
    printf '%7s  %-7s %-9s %-9s %-10s %-16s %-16s %s\n' \
      "$count" "$chain" "$in" "$out" "${proto% (*}" "$src" "$dst" "$dport"
  done

other=$(loki "$query_other" | jq -r '.data.result[0].value[1] // "0"')
echo "Port-less lines (ICMP and similar): ${other}"
echo "Raw lines in Grafana Explore: {job=\"router-syslog\"} |= \"${prefix}-\""
