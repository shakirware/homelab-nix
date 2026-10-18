# Undo firewall enforcement (local.firewall_enforce = true): back to observe
# mode. Arm with the dead-man before applying enforcement (docs/network.md).
:do { /ip firewall filter remove [find comment="zones: drop unmatched input from internal zones" or comment="zones: drop unmatched forward"] } on-error={ :log error "rollback enforce: drop rules" }
:do { /ip firewall filter set [find comment="zones: log unmatched input from internal zones"] log-prefix=FW-OBS-IN } on-error={ :log error "rollback enforce: input log" }
:do { /ip firewall filter set [find comment="zones: log unmatched forward"] log-prefix=FW-OBS-FWD } on-error={ :log error "rollback enforce: forward log" }
:log warning "deadman: rollback enforce complete"
