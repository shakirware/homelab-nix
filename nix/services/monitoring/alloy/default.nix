{ config, lib, pkgs, ... }:

# Ships the systemd journal to Loki. Other modules may drop further *.alloy
# files into /etc/alloy (e.g. router-syslog); component names must be unique.

let
  ips = config.homelab.ips;
  host = config.networking.hostName;

  lokiPushUrl = "http://${ips.monitoring}:3100/loki/api/v1/push";
in {
  services.alloy = {
    enable = true;
    # The HTTP server (UI and /metrics) stays on its default loopback address.
    extraFlags = [ "--disable-reporting" ];
  };

  environment.etc."alloy/journal.alloy".text = ''
    loki.write "default" {
      endpoint {
        url = "${lokiPushUrl}"
      }
    }

    loki.relabel "journal" {
      forward_to = []

      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
    }

    loki.source.journal "systemd" {
      max_age       = "12h"
      relabel_rules = loki.relabel.journal.rules
      labels        = {
        job  = "systemd-journal",
        host = "${host}",
      }
      forward_to = [loki.write.default.receiver]
    }
  '';
}
