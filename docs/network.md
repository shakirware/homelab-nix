# Network

A MikroTik hAP ax² routes the homelab's trusted, server and IoT networks. RouterOS
provides VLANs, Wi-Fi and a default-deny IPv4 firewall; AdGuard Home, Unbound,
Caddy and Tailscale run on `vm-gw`. Router configuration is managed primarily by
[OpenTofu](../infra/router), while host-side services use NixOS and Colmena.

This guide describes the deployed configuration. For day-to-day work, start with
[Operations](#operations); for access problems, see [Recovery](#recovery-and-secrets).

## Topology

| Zone | VLAN | Subnet | Purpose |
| --- | --- | --- | --- |
| **TRUSTED** | 1 (untagged) | `192.168.1.0/24` | Personal devices, admin workstation, Proxmox management |
| **SERVERS** | 20 | `192.168.20.0/24` | NixOS VMs and Proxmox's server-side interface |
| **CI** | 30 | `192.168.30.0/24` | `vm-ci` (`.10`), self-hosted GitHub Actions runners; internet only |
| **IOT** | 40 | `192.168.40.0/24` | TVs, Apple TVs, smart devices and the Reolink hub |
| **WAN** | — | PPPoE | Internet uplink |

| Interface | Connection |
| --- | --- |
| `ether1` | WAN |
| `ether2`, `ether3` | TRUSTED |
| `ether4` | Reolink hub on IOT |
| `ether5` | Proxmox trunk: VLAN 1 untagged, VLANs 20 and 30 tagged; no VLAN 40 |
| `wifi1-trusted`, `wifi2-trusted` | Trusted WPA2/WPA3 SSID on both radios, with 802.11r |
| `wifi1`, `wifi2` | Existing 5 GHz and 2.4 GHz SSIDs, assigned to IOT |

VLAN 1 remains untagged on the trusted network to preserve simple management
and recovery. The Proxmox host uses `192.168.1.100` for local administration
and `192.168.20.100` for VM-side services; these addresses are not freely
interchangeable because of its routing arrangement. IPv6 forwarding is
currently disabled pending a separate IPv6 policy.

## Firewall policy

The router uses RouterOS interface lists (`TRUSTED`, `SERVERS`, `IOT`, `CI`) as
zones.
Established and related traffic is accepted; **new connections not explicitly
permitted are dropped**. The policy lives in
[`firewall.tf`](../infra/router/firewall.tf). IOT is not part of the RouterOS
`LAN` interface list, and neither is CI.

| Source → destination | Permitted new connections |
| --- | --- |
| TRUSTED → internet / IOT | Unrestricted |
| TRUSTED → SERVERS | DNS and Caddy on `vm-gw`; direct Tailscale; Jellyfin and TuliProx on `vm-media`; ICMP |
| ADMIN → SERVERS | Unrestricted for the designated admin workstation |
| SERVERS → internet | Unrestricted |
| Home Assistant → IOT | Unrestricted from `vm-apps` |
| IOT → internet | Allowed, except DNS-over-TLS (TCP 853) |
| IOT → SERVERS | DNS, Caddy and ICMP to `vm-gw`; direct Jellyfin/TuliProx for registered TVs |
| IOT → TRUSTED | Restricted AirPlay receiver-to-sender UDP traffic, excluding ADMIN |
| CI → internet | Unrestricted, except private and CGNAT ranges |
| ADMIN → CI | SSH to `vm-ci` |
| `vm-monitoring` → CI | Node exporter (TCP 9100) on `vm-ci` |

The explicitly allowed direct service ports are:

| Client | Destination | Ports |
| --- | --- | --- |
| TRUSTED | `vm-gw` (`192.168.20.2`) | DNS UDP/TCP 53; Caddy TCP 80/443 and HTTP/3 UDP 443; Tailscale UDP 41641 |
| TRUSTED | `vm-media` (`192.168.20.120`) | Jellyfin TCP 8096; TuliProx TCP 8901 |
| IOT TVs / Apple TVs | `vm-media` | TCP 8096 and 8901 |

`TV_DEVICES` is populated from IoT reservations with the `tv` or `apple_tv`
role. TuliProx currently embeds the media VM's IP address in its playlists,
which is why direct TCP 8901 access is needed.

**Traffic to the router itself** is restricted to DHCP, multicast mDNS for its
repeater, management from authorised admin hosts, and the internal web-proxy
path from `vm-gw`. The router is not a DNS resolver. Its management services
also have source-address restrictions independent of the firewall.

Expected denials include UPnP/NAT-PMP probes, unicast mDNS addressed to the
router, unsuccessful public-IP hairpin attempts and direct access to
unapproved server ports. Only add an exception when a required feature is
actually affected.

### IoT controls

- **Wireless isolation:** access-list rules and a bridge horizon prevent IoT
  Wi-Fi clients from reaching one another. The wired Reolink hub on `ether4`
  is exempt from the Wi-Fi horizon. Review both mechanisms before introducing
  an accessory that requires local peer or hub access.
- **DNS:** DHCP advertises AdGuard. IoT DNS queries to other servers on
  UDP/TCP 53 are redirected there; TCP 853 is blocked. This is not a general
  block on DNS-over-HTTPS.
- **Scanner quarantine:** RouterOS identifies rapid port scans and temporarily
  blocks their source via `iot-scanners`.
- **Discovery:** RouterOS repeats multicast mDNS between TRUSTED and IOT;
  discovery does not override firewall permissions.

### CI network

VLAN 30 exists so the self-hosted runners can run repository code without
reaching anything else. Its `ci30:` rules in
[`firewall.tf`](../infra/router/firewall.tf) come first in each chain: CI
traffic to the router, to internal zones or to private ranges through the WAN
is dropped and logged (`FW-CI-*`), as are sources outside the subnet. IPv6 is
dropped both ways. `vm-ci` uses public DNS and NTP, so it needs nothing from
the router but routing. [`rollback/ci30.rsc`](../infra/router/rollback/ci30.rsc)
removes every `ci30:` object.

The runners themselves are described in
[`ci-runner`](../nix/services/ci-runner/default.nix): three ephemeral runners
in Ubuntu containers under rootless Docker, registered to a single repository
with the label `vm-ci`. The registration token lives in `secrets/vm-ci.yaml`
(a fine-grained PAT with repository Administration access) and never reaches
jobs.

`vm-ci` accepts SSH only from the admin workstation. Connect with the `vm-ci`
host alias in `~/.ssh/config`:

```sh
ssh vm-ci
```

## DNS and services

- **AdGuard Home → Unbound:** DNS for internal clients. Local service records
  resolve to `vm-gw`, where **Caddy** terminates HTTPS and reverse-proxies
  applications. The service record definitions live in
  [`records.nix`](../nix/modules/dns/records.nix).
- **Tailscale:** `vm-gw` advertises the server subnet; the tailnet's split DNS
  sends `shakr.dev` to AdGuard. Direct connections may use UDP 41641.
- **IoT DHCP:** a one-day lease on VLAN 40. Reserved addresses use
  `192.168.40.2–99`, with dynamic addresses in `192.168.40.100–199`.
  Reservations and device roles belong in the gitignored
  `infra/router/site.private.auto.tfvars`.
- **NFS:** `vm-storage` shares media with `vm-media` (read/write) and `vm-gw`
  (read-only). NixOS export permissions and an nftables guard limit access;
  applying export changes reloads rather than restarts NFS.
- **Router logging:** syslog goes to `vm-monitoring` and Loki. See
  [Monitoring](#monitoring-and-troubleshooting).

## Configuration ownership

| Managed by | Configuration |
| --- | --- |
| **OpenTofu** (`infra/router/`) | Managed bridge VLAN entries, VLAN 30 and 40 interfaces, VLAN 40 ports, IoT DHCP and reservations, trusted virtual Wi-Fi, firewall/NAT, DNS settings, logging, NTP, IPv6 and MAC access services |
| **NixOS / Colmena** (`nix/`) | DNS and proxy applications, NFS exports and guards, Home Assistant and monitoring |
| **SOPS / mise** (`secrets/env.yaml`) | Router API credential, trusted Wi-Fi passphrase and router-backup password |
| **Private local variables** (`site.private.auto.tfvars`) | Trusted SSID name and IoT MAC/IP inventory |
| **Manual RouterOS** | Bootstrap and account management, IP services, existing IoT radio SSIDs and country, VLAN 20, VLAN 1 DHCP and the remaining default bridge ports |

The manual boundary is intentional:

- [`bootstrap.rsc`](../infra/router/bootstrap.rsc) establishes the router-local
  CA, HTTPS API and `tofu` account; OpenTofu must not manage its own access.
- [`services.rsc`](../infra/router/services.rsc) defines IP service exposure;
  provider 1.99.1 cannot reliably import/read these services.
- [`users.rsc`](../infra/router/users.rsc) documents operator-managed accounts;
  account mistakes cannot be automatically rolled back through Netwatch.
- Existing IoT SSIDs and their security profiles remain outside OpenTofu to
  avoid exposing passwords through the provider's Wi-Fi security attributes.
- VLAN 20 and VLAN 1 DHCP remain in the established RouterOS configuration;
  they do not need adoption to operate correctly.

`local.iot_tag = "phase4"` is **a live RouterOS comment identifier**, not a
deployment flag. Changing it would modify existing IoT access-list entries
and disconnect wireless clients. Do not rename it for cosmetic reasons.

## Operations

### Change the router safely

Use a router-local rollback for any change that could interrupt access or
network services. RouterOS `home` device-mode disables the scheduler, so the
rollback uses **Netwatch**, not a laptop timer.

1. Back up the current state and write an `.rsc` script that reverses the
   intended change. Select stable object names/comments and avoid dynamic
   entries.
2. Upload the script as `rollback.rsc`, check it parses with
   `/import file-name=rollback.rsc verbose=yes dry-run`, then arm Netwatch:

   ```routeros
   /tool netwatch add host=192.0.2.1 type=icmp interval=20s timeout=1s start-delay=20m \
       comment="deadman: auto-rollback" \
       down-script="/import file-name=rollback.rsc; /tool netwatch remove [find comment~\"^deadman\"]"
   ```

   Verify that it is armed, that the script has the required permissions and
   that the timeout exceeds the testing window.
3. Run `make router-plan`; examine the saved plan, including replacements and
   deletions. Run `make router-apply` only when the plan is understood.
4. Verify management, both Wi-Fi networks, DNS, remote access, Home Assistant,
   media playback and monitoring. Check for newly blocked legitimate flows.
5. Disarm Netwatch **only after** successful checks. Remove temporary router
   files and run [`backup-state.sh`](../infra/router/backup-state.sh).

`router-apply` uses the previously saved plan and rejects resource destruction
or replacement without `ALLOW_DESTROY=1`. Saved plans and state contain
secrets; handle them as private files. Extending a dead-man timer requires
arming its replacement **before** removing the old one. Netwatch cannot
reliably undo account and credential changes; verify those separately.
If the main default-deny policy must be disabled, use
[`rollback/enforce.rsc`](../infra/router/rollback/enforce.rsc), set
`local.firewall_enforce = false` in [`locals.tf`](../infra/router/locals.tf)
and reconcile OpenTofu state with a reviewed plan.

### Common changes

| Task | Where to start |
| --- | --- |
| Add an IoT device | Add its reservation and role to `site.private.auto.tfvars`, plan/apply, then update any application integration that uses its address |
| Allow a new service | Inspect actual drops; add the narrowest required rule to [`firewall.tf`](../infra/router/firewall.tf), including its position in the ordered chain |
| Add a network zone | Define addressing, VLAN membership, DHCP/DNS and explicit ingress/egress policy together; validate trunk membership and rollback before applying |
| Add an admin device | Update `local.admin_hosts`, restricted IP services and DHCP reservation together; verify a separate recovery path first |
| Change trusted Wi-Fi credentials | Update SOPS, prepare a router-local rollback, update the trusted security profile via admin SSH, then reconnect and verify clients |
| Change IoT Wi-Fi credentials | Use the manual radio profiles and plan for all IoT clients to reconnect |
| Rotate the `tofu` API credential | Update SOPS and the router account via admin SSH stdin; verify new API access and expiry of older authenticated sessions |

Pass secret values over stdin and avoid writing them in process arguments,
logs or documentation. SOPS holds `TF_VAR_routeros_password`,
`TF_VAR_trusted_wifi_passphrase` and `ROUTER_BACKUP_PASSWORD`. The trusted
Wi-Fi passphrase is intentionally ignored for subsequent OpenTofu updates
because the automation account reads it masked;
updating SOPS alone does **not** rotate the live SSID.

## Monitoring and troubleshooting

Router syslog is received on `vm-monitoring:1514/udp` and retained in Loki
for 30 days. The relevant labels and prefixes are:

| Purpose | Where to look |
| --- | --- |
| Default-deny firewall drops | `infra/router/review-observations.sh 24` |
| IoT firewall drops | Grafana Explore: `{job="router-syslog"} \|= "FW-IOT"` |
| Raw router denials | Grafana Explore: `{job="router-syslog"} \|= "FW-DROP"` |
| Service health | Prometheus targets, Blackbox probes, systemd status and application logs |

For a newly broken service, first confirm the client's VLAN and destination
address, then match its traffic to a drop log. Distinguish blocked new
connections from expected noise and stale conntrack replies. Verify the
specific service works before widening an allow rule.

## Recovery and secrets

| Failure | Recovery path |
| --- | --- |
| A guarded router change cuts access | Let the verified Netwatch rollback run; do not disable it prematurely |
| Trusted Wi-Fi fails but WAN and SERVERS work | Use a phone hotspot and Tailscale to reach `vm-monitoring` or the internal router WebFig endpoint through `vm-gw` |
| The admin workstation is unavailable | Use MAC-WinBox from another TRUSTED device; a separate-device password login is **not yet verified** |
| Router configuration must be restored | Use the encrypted RouterOS binary backup and `ROUTER_BACKUP_PASSWORD` from SOPS; restoring reboots the router |
| No management path works | Physical console/reset and RouterOS recovery tools |

The factory administrator account is intentionally retained pending an
independent MAC-WinBox recovery test. Do not disable it on the assumption that
recovery has already been proven.

**State and backups:**

- `infra/router/terraform.tfstate`, its backups and saved plans contain
  sensitive data (including the trusted Wi-Fi passphrase). Keep them
  gitignored with restrictive permissions.
- Run [`backup-state.sh`](../infra/router/backup-state.sh) after every router
  apply. It stores an age-encrypted state copy on `vm-storage`, separate from
  the NFS-shared media directory. Test decryption after changing age keys.
- Keep a password-encrypted RouterOS `.backup` and an export after meaningful
  changes. The encryption password is `ROUTER_BACKUP_PASSWORD` in SOPS.
  Generate the binary backup on the router with its password sent over an
  encrypted SSH session, then copy it off-router. For a redacted text export:

  ```sh
  ssh router /export > ~/.local/share/homelab/router-backups/router-current.rsc
  ```

- Use `secrets/env.yaml` with SOPS/mise for credentials, never plaintext
  secrets in committed Terraform variables or documentation.

## Known limitations

- **Proxmox host:** management firewall and SSH hardening are deferred; VM
  backup schedules and off-site VM backup storage are not yet deployed.
- **Unmanaged router objects:** VLAN 20 and VLAN 1 DHCP are intentionally
  maintained outside OpenTofu for now.
- **Media URLs:** TuliProx playlists currently refer directly to `vm-media`;
  changing that requires regenerating clients' playlists and reviewing the
  matching firewall rules.

