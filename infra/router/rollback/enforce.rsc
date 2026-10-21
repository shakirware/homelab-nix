# Back to observe mode: removes the two default-deny rules and restores the
# FW-OBS log prefixes. Run by hand or as the dead-man rollback for firewall
# changes, then set firewall_enforce = false and apply (docs/network.md).
:do { /ip firewall filter remove [find comment="zones: drop unmatched input from internal zones" or comment="zones: drop unmatched forward"] } on-error={ :log error "rollback enforce: drop rules" }
:do { /ip firewall filter set [find comment="zones: log unmatched input from internal zones"] log-prefix=FW-OBS-IN } on-error={ :log error "rollback enforce: input log" }
:do { /ip firewall filter set [find comment="zones: log unmatched forward"] log-prefix=FW-OBS-FWD } on-error={ :log error "rollback enforce: forward log" }
:log warning "deadman: rollback enforce complete"
