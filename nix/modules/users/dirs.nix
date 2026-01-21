{ lib, config, ... }:

let user = config.homelab.ids.user;
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d /srv 0755 root root - -"
    "d /srv/appdata 2775 ${user} media - -"
    "d /srv/downloads 2775 ${user} media - -"
  ];
}
