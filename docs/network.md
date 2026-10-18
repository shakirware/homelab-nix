# Network

A MikroTik hAP ax² (RouterOS 7.19, device-mode `home`) routes three internal
zones. It is managed with OpenTofu in [`infra/router`](../infra/router),
except for what is listed under [Set by hand](#set-by-hand). The NixOS side
(NFS exports, host guards, the log receiver) is managed with Colmena.

## Zones

| Zone | VLAN | Subnet | Router interface | Contents |
| --- | --- | --- | --- | --- |
| TRUSTED | 1 (untagged) | 192.168.1.0/24 | `bridge` | Workstation (.74), phones, Proxmox (.100) |
| SERVERS | 20 | 192.168.20.0/24 | `vlan20` | The NixOS VMs |
| IOT | 40 | 192.168.40.0/24 | `vlan40-iot` | IoT devices, TVs, Apple TVs, Reolink hub, guests |
| WAN | — | PPPoE | `pppoe-out1` | Internet |

| Port or SSID | Zone |
| --- | --- |
| ether1 | WAN |
| ether2, ether3 | TRUSTED |
| ether4 | IOT (Reolink Home Hub) |
| ether5 | Proxmox trunk: VLAN 1 untagged, VLAN 20 tagged, never VLAN 40 |
| trusted SSID (`wifi1-trusted`, `wifi2-trusted`; WPA2/WPA3, 802.11r) | TRUSTED |
| the radios' original SSIDs (`wifi1` 5 GHz, `wifi2` 2.4 GHz) | IOT |

Devices that only know the original SSIDs land on IOT automatically: their
password now grants internet access and nothing else. TRUSTED stays on
untagged VLAN 1 because, with one router and no downstream switches,
renumbering it would add risk without adding isolation.

## Policy

Rules match new connections between zones ([`firewall.tf`](../infra/router/firewall.tf)).

| From → To | Allowed |
| --- | --- |
| TRUSTED → internet | everything |
| TRUSTED → SERVERS | AdGuard DNS and Caddy on vm-gw (53, 80, 443); ping |
| TRUSTED → IOT | everything (apps, casting, AirPlay) |
| ADMIN hosts → SERVERS | everything |
| SERVERS → internet | everything |
| Home Assistant → IOT | everything |
| IOT → internet | everything except DNS-over-TLS |
| IOT → SERVERS | AdGuard (DNS, ping) and Caddy on vm-gw; Apple TVs and TVs also Jellyfin and TuliProx on vm-media (8096, 8901) |
| IOT → TRUSTED | AirPlay return traffic (UDP) from Apple TVs and TVs, never to ADMIN hosts |

The router itself accepts DHCP from TRUSTED and IOT, mDNS for the repeater,
management (SSH, WinBox, HTTP, HTTPS) from ADMIN hosts only, and HTTP from
vm-gw for `router.shakr.dev`. It answers no DNS, and IPv6 forwarding is off.

Everything else:

- **From IOT:** dropped and logged (`FW-IOT-DROP`, `FW-IOT-IN`) now.
- **From TRUSTED and SERVERS:** logged (`FW-OBS-*`) but not yet dropped. See
  [Enforcing the firewall](#enforcing-the-firewall).

The IOT zone also has these controls:

| Control | How |
| --- | --- |
| DHCP | server `iot`, authoritative, 1-day leases; reservations .2–.99 from `site.private.auto.tfvars`, pool .100–.199 |
| Client isolation | access-list entries on `wifi1`/`wifi2` plus a shared bridge horizon: IoT Wi-Fi clients cannot reach each other. The hub on ether4 has no horizon and still reaches its Wi-Fi camera |
| DNS | handed out as AdGuard; port 53 to any other resolver is redirected to AdGuard; TCP 853 is dropped |
| Port scanners | 21 ports in 3 s quarantines the source for a day |
| Discovery | the router repeats mDNS between `bridge` and `vlan40-iot`, so AirPlay and vendor apps find devices across zones |

No IoT device is a HomeKit or Matter accessory, so isolation costs nothing
locally. If one ever needs a local hub (an Apple TV or Echo), add an
access-list exemption for it before the per-radio entries and drop the
horizon.

## Making a change

Device-mode `home` disables the scheduler, so the dead-man switch is a
**netwatch** entry on an address that never answers. It runs its
down-script after `start-delay` unless removed, on the router itself.

1. Write the inverse of the change as an `.rsc` script. Wrap each step in
   `:do { … } on-error={ … }` and select by comment or name, ignoring dynamic
   entries (`!dynamic`). Upload it and check it parses:
   `scp rollback.rsc router:` then
   `/import file-name=rollback.rsc verbose=yes dry-run`.
2. Arm the dead-man:

   ```
   /tool netwatch add host=192.0.2.1 type=icmp interval=20s timeout=1s start-delay=10m \
       comment="deadman: auto-rollback" \
       down-script="/import file-name=rollback.rsc; /tool netwatch remove [find comment~\"^deadman\"]"
   ```

3. `make router-plan`, review it, then `make router-apply`. It applies only
   that saved plan (mode 600: it holds secrets), and refuses one that
   destroys or replaces anything unless run with `ALLOW_DESTROY=1`.
4. Check: Wi-Fi and internet on both SSIDs, DNS, `ssh router`, `ssh pve`,
   Home Assistant, `router.shakr.dev`, and 44/44 Prometheus targets with no
   alerts.
5. If every check passes, disarm with
   `/tool netwatch remove [find comment~"^deadman"]` and delete the script.

Netwatch scripts lack the `policy` right, so a dead-man **cannot undo account
changes**. [`users.rsc`](../infra/router/users.rsc) and the `tofu` address
are operator steps, verified one at a time.

### Routine tasks

| Task | How |
| --- | --- |
| Add or move an IoT device | add a reservation to `site.private.auto.tfvars` (role `tv` or `apple_tv` for AirPlay and media access), plan, apply, reconnect the device |
| Point Home Assistant at an IoT device | Reconfigure the integration with the 192.168.40.x address. If the dialog times out, stop the container and edit the host in `/srv/appdata/home-assistant/config/.storage/core.config_entries` on vm-apps (back it up first) |
| Rotate the trusted passphrase | new value in `secrets/env.yaml` (`sops set --value-stdin`), then as `shakir`: `/interface wifi security set [find name=trusted] passphrase=…`. OpenTofu ignores the passphrase after creation because the `tofu` account can only read it masked |
| Rotate the `tofu` password | generate it into `secrets/env.yaml` (`sops set --value-stdin`), then send `/user set [find name=tofu] password=…` over `ssh -T router` stdin, so it never appears on a command line or in the router log. REST sessions opened with the old password keep working for up to 10 minutes |
| Change an IoT SSID or its password | by hand on `wifi1`/`wifi2`: every IoT device has to re-join |

### Enforcing the firewall

Observation of TRUSTED and SERVERS started 2026-10-18 13:08 BST.

1. Review with `infra/router/review-observations.sh 48`, or in Grafana with
   `{job="router-syslog"} |= "FW-OBS"`.
2. For every legitimate flow, add an accept rule (scoped to its source,
   destination and port). Known harmless flows:
   - Tailscale probing the router for NAT-PMP/UPnP (UDP 5351, 1900);
   - Tailscale hairpin attempts to the public address;
   - an iPhone's direct Tailscale path to vm-gw (UDP 41641), which falls back
     to a relay.
3. Set `firewall_enforce = true` in [`locals.tf`](../infra/router/locals.tf).
   Plan, then apply under the dead-man with
   [`rollback/enforce.rsc`](../infra/router/rollback/enforce.rsc) armed. It
   returns the router to observe mode.
4. Keep reviewing with `PREFIX=FW-DROP` for a few days.

## Recovery

| If… | Then |
| --- | --- |
| a change cuts access | wait for the dead-man |
| the house Wi-Fi is down | phone hotspot on the laptop, `tailscale up` (vm-gw advertises 192.168.20.0/24 and is the exit node): `ssh vm-monitoring`, and `https://router.shakr.dev` as `shakir` (WebFig, full admin, with a Terminal). Only while away from the house Wi-Fi, because with Tailscale up at home the laptop reaches the servers through vm-gw instead of as .74. This path needs the router's WAN and VLAN 20 to work |
| the workstation is lost | **MAC-WinBox** from any computer on TRUSTED as `shakir` (password in the password manager). It works at layer 2, regardless of addresses and firewall rules. Then add the new address to `admin_hosts`, `services.rsc` and a pinned lease |
| the configuration is broken beyond that | restore the latest `.backup` from the router's flash (password: `ROUTER_BACKUP_PASSWORD`) |
| nothing else works | physical reset and Netinstall |

MAC-WinBox reachability is verified, but a password login over it has not
been tested yet, so the factory `admin` account stays enabled.

## Accounts

| Account | Group | Login | Owner |
| --- | --- | --- | --- |
| `shakir` | full | SSH key `shakir@homelab-laptop` (`ssh router`); password for WinBox and WebFig | operator (`users.rsc`) |
| `admin` | full | SSH key; password | factory account; disabled once MAC-WinBox recovery is tested (`users.rsc` step 4) |
| `tofu` | iac | REST API over HTTPS from 192.168.1.74 | `bootstrap.rsc`; password in `secrets/env.yaml` |

## State, secrets and backups

- **State:** `infra/router/terraform.tfstate` is local, gitignored and mode
  600. It contains the trusted passphrase, so treat it and its copies in
  `~/.local/share/homelab/router-state/` as secrets. Back it up before any
  `tofu state` command, and after every apply run
  [`backup-state.sh`](../infra/router/backup-state.sh): it keeps an
  age-encrypted copy in `vm-storage:~/backups/router-state/` (restore with
  `age -d -i "$SOPS_AGE_KEY_FILE"`).
- **Private inputs:** `site.private.auto.tfvars` holds the trusted SSID and
  the IoT reservations (MAC addresses).
- **Credentials:** the `tofu` password, the trusted passphrase and the router
  backup password are in `secrets/env.yaml`, loaded by mise.

**Router backups:** one encrypted `.backup` on the router's flash, with a copy
in `~/.local/share/homelab/router-backups/`, plus `.rsc` exports there that
hide sensitive values. Replace both after any significant change:

```sh
printf '/system backup save name=<name> encryption=aes-sha256 password="%s"\n' \
  "$ROUTER_BACKUP_PASSWORD" | ssh -T router
scp router:<name>.backup ~/.local/share/homelab/router-backups/
ssh router /export > ~/.local/share/homelab/router-backups/<name>.rsc
```

Restoring a `.backup` needs `ROUTER_BACKUP_PASSWORD` and reboots the router.

## Set by hand

These are the source of truth for what OpenTofu does not manage. Each is
manual on purpose.

| Item | Source of truth | Why not OpenTofu |
| --- | --- | --- |
| IP services (SSH, WinBox, web, API) | [`services.rsc`](../infra/router/services.rsc), idempotent | `routeros_ip_service` (provider 1.99.1) cannot import and resolves services by name, which is ambiguous |
| Accounts (`shakir`, `admin`) | [`users.rsc`](../infra/router/users.rsc), operator steps | `routeros_system_user` keeps passwords in state, and a dead-man cannot undo an account change, so a bad apply could lock the router |
| CA, HTTPS certificate, `iac` group, `tofu` user | [`bootstrap.rsc`](../infra/router/bootstrap.rsc), once | OpenTofu must not own its own access; key material stays on the router |
| IoT SSIDs and passwords (inline on `wifi1`/`wifi2`) | the router | `routeros_wifi` stores `security` as a non-sensitive map, so the passwords would land in state and plan output; changing them re-joins every IoT device |
| Wi-Fi country `United Kingdom` | the router: `/interface wifi set [find default-name=wifi1 or default-name=wifi2] configuration.country="United Kingdom"` | part of the same radio objects |
| VLAN 20 (bridge entry `*4`, `vlan20`, 192.168.20.1/24) | the router | not yet adopted; can move to OpenTofu (import-only, no change) |
| VLAN 1 DHCP (server `defconf`, pool `default-dhcp`, network, the pinned 192.168.1.74 lease) | the router | not yet adopted; can move to OpenTofu (import-only, no change) |
| Bridge, ports ether2, ether3, ether5 | the router (defconf) | the bridge object has many computed settings and carries every network; low value, high blast radius |

## Router logs

The router sends `info`, `warning`, `error` and `critical` to
`vm-monitoring:1514/udp`
([`router-syslog`](../nix/services/monitoring/router-syslog)), which stores
them in Loki as `job="router-syslog"`. Only the router's VLAN 20 address may
send.

Loki keeps 30 days of logs: its compactor enforces `retention_period`.
