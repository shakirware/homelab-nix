# Network

A MikroTik hAP ax² routes five network zones: trusted devices, servers, CI,
releases and IoT. RouterOS provides VLANs, Wi-Fi and a default-deny IPv4 firewall, while
`vm-gw` provides DNS, reverse proxying and remote access. Router configuration
is managed primarily through [OpenTofu](../infra/router); guest services are
configured with NixOS and deployed using Colmena.

This guide describes the deployed network, its boundaries and the reasoning
behind them.

## Topology

| Zone | VLAN | Subnet | Purpose |
| --- | --- | --- | --- |
| **TRUSTED** | 1 (untagged) | `192.168.1.0/24` | Personal devices and Proxmox management |
| **SERVERS** | 20 | `192.168.20.0/24` | NixOS VMs and server-side services |
| **CI** | 30 | `192.168.30.0/24` | Isolated self-hosted GitHub Actions runners |
| **RELEASE** | 31 | `192.168.31.0/24` | The release runner, which holds production deploy access |
| **IOT** | 40 | `192.168.40.0/24` | TVs, smart-home devices and the Reolink hub |
| **WAN** | — | PPPoE | Internet uplink |

The Proxmox uplink (`ether5`) carries VLAN 1 untagged and VLANs 20, 30 and
31 tagged; VLAN 40 does not extend to Proxmox. Keeping trusted management on the
untagged VLAN provides a simpler recovery path. The Proxmox management and
server-side interfaces use separate addresses with different routing roles.

IPv6 forwarding remains disabled pending a separate firewall policy.

## Firewall policy

RouterOS interface lists (`TRUSTED`, `SERVERS`, `IOT`, `CI`, `RELEASE`) define security
zones. Established and related connections are allowed, but **new connections
are denied unless explicitly permitted**. The policy is defined in
[`firewall.tf`](../infra/router/firewall.tf). None of IOT, CI and RELEASE belongs to
the RouterOS `LAN` interface list.

| Source → destination | Permitted new connections |
| --- | --- |
| TRUSTED → internet / IOT | Unrestricted |
| TRUSTED → SERVERS | DNS and Caddy on `vm-gw`; Tailscale; Jellyfin and TuliProx on `vm-media`; ICMP |
| ADMIN → SERVERS | Administrative access from a designated workstation |
| SERVERS → internet | Unrestricted |
| Home Assistant → IOT | Access from `vm-apps` |
| IOT → internet | Allowed, except DNS-over-TLS (TCP 853) |
| IOT → SERVERS | DNS, Caddy and ICMP on `vm-gw`; direct Jellyfin/TuliProx access for registered TVs |
| IOT → TRUSTED | Restricted AirPlay UDP traffic, excluding administrative hosts |
| CI → internet | Outbound access, excluding private and CGNAT address ranges |
| ADMIN → CI | SSH to `vm-ci` |
| `vm-monitoring` → CI | Node Exporter metrics (TCP 9100) |
| RELEASE → internet | Outbound access, excluding private and CGNAT address ranges |
| ADMIN → RELEASE | SSH to `vm-release` |
| `vm-monitoring` → RELEASE | Node Exporter metrics (TCP 9100) |

Direct service access is limited to the ports the clients actually need:

| Client | Destination | Ports |
| --- | --- | --- |
| TRUSTED | `vm-gw` | DNS 53; Caddy TCP 80/443 and HTTP/3 UDP 443; Tailscale UDP 41641 |
| TRUSTED | `vm-media` | Jellyfin TCP 8096; TuliProx TCP 8901 |
| Registered IoT TVs | `vm-media` | TCP 8096 and 8901 |

TV access is based on device roles in the IoT reservations. TuliProx playlists
contain a direct media-server address, so access to TCP 8901 must be allowed
without going through Caddy.

Traffic **to the router itself** is separately restricted to DHCP, mDNS
repeating, authorised management and the internal web-proxy path. Management
services also enforce source-address restrictions. Expected firewall drops
include UPnP/NAT-PMP discovery and attempts to reach unapproved ports; those
do not, by themselves, indicate an outage.

### Per-VM service guards

The VLAN 20 VMs share one subnet, so the router cannot filter traffic between
them; each VM's own nftables firewall is the only control. Podman DNATs
published container ports before the NixOS `input` chain, so
`networking.firewall.allowedTCPPorts` does not govern them. Every listening
service port is instead declared in `homelab.firewall.restrict`
([`backend-guard.nix`](../nix/modules/networking/backend-guard.nix)), which
builds one `backend-guard` table per host at `prerouting` priority -150, ahead
of the DNAT, and so covers containers and native services alike.

| Port class | Allowed sources |
| --- | --- |
| Web applications behind Caddy | `vm-gw` |
| Jellyfin, TuliProx | `vm-gw`, TRUSTED and IOT subnets (the router narrows these further) |
| NetV, Home Assistant | `vm-gw`, TRUSTED subnet |
| Loki push (3100) | Every VLAN 20 VM |
| restic REST server, NFS | The backup clients; the NFS clients |
| Node Exporter (9100) | `vm-monitoring` |
| SSH on the VLAN 20 VMs | Administrative workstation, `vm-gw` |
| SSH on `vm-gw` | Administrative workstation, Tailscale addresses |
| SSH on `vm-ci`, `vm-release` | Administrative workstation |

Anything else, IPv6 included, is dropped. A build fails if a container
publishes a port that has no entry. Containers may reach restricted ports
through their own host's address only on `vm-media`
(`homelab.firewall.allowLocalContainers`), where the media applications call
each other that way; Cleanuparr, Pinchflat and the Gluetun control port opt
out. Services on the host network or running natively (Prometheus, Grafana,
Loki, Alertmanager, Home Assistant, Vaultwarden, AdGuard) still need their
`allowedTCPPorts` entry as well.

### IoT isolation

- **Client isolation:** Wi-Fi access lists and bridge horizons prevent IoT
  wireless clients from reaching one another. Wired devices are not subject to
  the same wireless horizon.
- **DNS policy:** IoT clients use AdGuard; other DNS traffic on UDP/TCP 53 is
  redirected there, and DNS-over-TLS on TCP 853 is blocked. This does not block
  DNS-over-HTTPS generally.
- **Discovery:** RouterOS repeats mDNS between TRUSTED and IOT, while the
  firewall still controls which connections are allowed.
- **Scan protection:** Rapid port scanners can be temporarily quarantined by
  RouterOS address-list rules.

### Isolated CI network

VLAN 30 lets self-hosted runners execute repository code without access to the
rest of the homelab. CI can initiate connections to the internet, but not to
other internal zones, router management or private networks via the WAN. The
[`ci30:` firewall rules](../infra/router/firewall.tf) enforce and log these
denials; IPv6 traffic is blocked in both directions.

Restricted **inbound** exceptions allow SSH from the administrative workstation
and metrics scraping from `vm-monitoring`. These do not give CI permission to
initiate connections back into production networks. Public DNS and NTP avoid
dependencies on internal services.

The [runner module](../nix/services/ci-runner/default.nix) defines three
ephemeral GitHub Actions runners in Ubuntu containers using rootless Docker.
Runner workspaces and test environments are isolated, and registration
credentials are SOPS-encrypted and not exposed to CI jobs. CI logs stay local
because the isolated VLAN cannot reach Loki.

### Release network

VLAN 31 holds `vm-release`, the only machine with production deploy access.
It has the same policy as CI (internet only, SSH from the administrative
workstation, metrics from `vm-monitoring`) under its own
[`rel31:` rules](../infra/router/release.tf), and the two VLANs cannot reach
each other.

Its runner is registered to a separate private release repository rather
than the application repository, so a pull request cannot schedule a job on it:
GitHub only hands the runner jobs from that repository. Removing the VLAN uses
[`rollback/rel31.rsc`](../infra/router/rollback/rel31.rsc).

## DNS and shared services

- **DNS and ingress:** AdGuard Home forwards through Unbound. Internal service
  records resolve to `vm-gw`, where Caddy provides HTTPS and reverse proxying.
  Records are defined in [`records.nix`](../nix/modules/dns/records.nix):
  one `webHosts` entry per web service gives its DNS record on `vm-gw`, its
  Caddy vhost and its Blackbox health probe (`probePath`, default `/`).
- **Remote access:** Tailscale advertises the server subnet, with split DNS for
  internal names and direct connections where permitted by the firewall.
  Immich is reached the same way as the other services: through Caddy on
  `vm-gw`, from the LAN or over Tailscale, and is not exposed to the internet.
- **IoT addressing:** DHCP and device reservations are defined through RouterOS
  and private OpenTofu variables, with device roles used by firewall rules.
- **Shared storage:** `vm-storage` exports an NFSv4 root at `/export` with two
  bind-mounted children: `/media` (the mergerfs pool) for `vm-media`
  (read/write) and `vm-gw` (read-only), and `/photos` (`/srv/diskA/photos`,
  outside the pool) for `vm-apps` only (read/write, `sync`, all users squashed
  to 1000:1001). Clients mount `192.168.20.110:/media` or `:/photos`. A client
  without a child export gets permission denied, and a host firewall limits
  port 2049 to the three clients.
- **Router logs:** RouterOS forwards syslog to `vm-monitoring` for collection
  in Loki.

## Configuration ownership

| Managed by | Responsibility |
| --- | --- |
| **OpenTofu** ([`infra/router/`](../infra/router)) | Managed VLANs, firewall/NAT rules, IoT DHCP and reservations, selected Wi-Fi settings, logging and network services |
| **NixOS / Colmena** ([`nix/`](../nix)) | DNS, reverse proxy, NFS, application services and monitoring |
| **SOPS / mise** | Encrypted router credentials, Wi-Fi secrets and backup credentials |
| **Private OpenTofu variables** | Site-specific SSIDs, reservations and device inventory |
| **Manual RouterOS configuration** | Bootstrap, accounts, selected management services, existing SSIDs, VLAN 20 and VLAN 1 DHCP |

Some boundaries are intentionally manual. [`bootstrap.rsc`](../infra/router/bootstrap.rsc)
creates the API access OpenTofu needs; managing that access through the same
provider could lock it out. Router management services and accounts are
covered by [`services.rsc`](../infra/router/services.rsc) and
[`users.rsc`](../infra/router/users.rsc). Existing Wi-Fi security profiles
remain outside OpenTofu to avoid exposing credentials through provider state.

RouterOS object comments can also act as identifiers for managed resources;
renaming them without understanding their use can recreate rules or interrupt
wireless access.

## Change safety

Router changes that could interrupt access are protected by a **router-local
dead-man rollback**: a reviewed RouterOS script reverses the change unless a
Netwatch check is disarmed after the change is verified. Netwatch is used
because RouterOS `home` device-mode disables the scheduler. Recovery scripts are
in [`infra/router/rollback/`](../infra/router/rollback).

Applies run from a saved OpenTofu plan, and the Makefile refuses plans that
destroy or replace resources unless that is explicitly allowed. Account and
credential changes sit outside this net, because a network rollback cannot
reliably undo them. The trusted Wi-Fi passphrase is also rotated by hand: the
automation account can only read the existing value in masked form.

## Monitoring

Router syslog is sent to `vm-monitoring` and retained in Loki. Firewall rules
log with zone prefixes (`FW-IOT`, `FW-DROP`, `FW-CI-*`, `FW-REL-*`), so denied
traffic can be traced to its source zone, and
[`review-observations.sh`](../infra/router/review-observations.sh) summarises
those observations. Prometheus and Blackbox Exporter independently check
infrastructure and service health, and the NFS mounts on `vm-media` and `vm-apps`
are probed on the host and inside the containers that use them.

## State and backups

OpenTofu state and saved plans can contain secrets and are kept out of Git with
restricted permissions. `make router-apply` runs
[`backup-state.sh`](../infra/router/backup-state.sh) after each apply to store
an age-encrypted copy of the state on `vm-storage`, outside the shared media
directory, and preserves the RouterOS configuration as a password-encrypted
binary backup and a redacted export.

## Known limitations

- **Proxmox management:** There is no host firewall or SSH hardening;
  management access relies on the router's zone firewall.
- **Router configuration:** Some existing VLAN and DHCP settings remain outside
  OpenTofu. Independent router access recovery is not fully verified.
- **Photos export:** `/export/photos` is a subdirectory of the `diskA`
  filesystem exported with `no_subtree_check`. Root on `vm-apps` could forge
  file handles for other `diskA` files (the media); `subtree_check` would close
  this but breaks on the renames Immich does. Photos are not reachable from
  `vm-media` or `vm-gw`.
- **Media clients:** TuliProx playlists currently contain a direct media-server
  address; changing it requires updating playlists and the corresponding
  firewall policy.

