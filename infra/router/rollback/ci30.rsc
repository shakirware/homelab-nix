# Removes VLAN 30 (CI): every object commented "ci30:", rules first so
# nothing is left referring to the list or interface. Safe to run twice.
# Leaves OpenTofu state stale: afterwards revert ci.tf and the "ci30:" rules,
# then plan and apply (docs/network.md).
:do { /ip firewall filter remove [find comment~"^ci30:"] } on-error={ :log error "rollback ci30: ipv4 rules" }
:do { /ipv6 firewall filter remove [find comment~"^ci30:"] } on-error={ :log error "rollback ci30: ipv6 rules" }
:do { /ip firewall address-list remove [find list=CI_BLOCKED comment~"^ci30:"] } on-error={ :log error "rollback ci30: address list" }
:do { /interface list member remove [find comment~"^ci30:"] } on-error={ :log error "rollback ci30: list member" }
:do { /interface list remove [find name=CI comment~"^ci30:"] } on-error={ :log error "rollback ci30: list" }
:do { /ip address remove [find comment~"^ci30:"] } on-error={ :log error "rollback ci30: address" }
:do { /interface vlan remove [find name=vlan30-ci comment~"^ci30:"] } on-error={ :log error "rollback ci30: vlan" }
:do { /interface bridge vlan remove [find vlan-ids=30 comment~"^ci30:"] } on-error={ :log error "rollback ci30: bridge vlan" }
:log warning "deadman: rollback ci30 complete"
