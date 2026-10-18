# Router IP services. Idempotent: safe to re-run after any change.
# Kept outside OpenTofu because routeros_ip_service in provider 1.99.1 cannot
# import or reliably read services (see services.tf). Apply under the dead-man
# switch (docs/network.md).
#
# Management is reachable only from the admin workstation; the web UI also
# from vm-gw (192.168.20.2), which serves router.shakr.dev. www-ssl is
# OpenTofu's REST endpoint (bootstrap.rsc) and is left as bootstrapped.
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/ip service set ssh address=192.168.1.74/32 disabled=no
/ip service set winbox address=192.168.1.74/32 disabled=no
/ip service set www address=192.168.1.74/32,192.168.20.2/32 disabled=no
