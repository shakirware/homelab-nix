# Removes VLAN 31 (release): every object commented "rel31:", rules first so
# nothing is left referring to the list or interface. Safe to run twice.
# Leaves OpenTofu state stale: afterwards revert release.tf and the "rel31:"
# rules, then plan and apply (docs/network.md).
:do { /ip firewall filter remove [find comment~"^rel31:"] } on-error={ :log error "rollback rel31: ipv4 rules" }
:do { /ipv6 firewall filter remove [find comment~"^rel31:"] } on-error={ :log error "rollback rel31: ipv6 rules" }
:do { /ip firewall address-list remove [find list=RELEASE_BLOCKED comment~"^rel31:"] } on-error={ :log error "rollback rel31: address list" }
:do { /interface list member remove [find comment~"^rel31:"] } on-error={ :log error "rollback rel31: list member" }
:do { /interface list remove [find name=RELEASE comment~"^rel31:"] } on-error={ :log error "rollback rel31: list" }
:do { /ip address remove [find comment~"^rel31:"] } on-error={ :log error "rollback rel31: address" }
:do { /interface vlan remove [find name=vlan31-release comment~"^rel31:"] } on-error={ :log error "rollback rel31: vlan" }
:do { /interface bridge vlan remove [find vlan-ids=31 comment~"^rel31:"] } on-error={ :log error "rollback rel31: bridge vlan" }
:log warning "deadman: rollback rel31 complete"
