{ config, lib, pkgs, ... }:

# External dead-man's switch for the monitoring stack.
#
# Every 5 minutes vm-monitoring verifies the local alerting pipeline
# (Prometheus ready, Alertmanager ready, and the always-firing Watchdog alert
# present in Alertmanager) and only then pings an external heartbeat URL
# (e.g. a healthchecks.io check). The external service alerts when pings stop,
# which covers vm-monitoring dying, the alerting pipeline breaking, and
# WAN/DNS outages that also block Telegram.
#
# To enable:
#   1. Create a check with a ~10 min period and grace at your provider.
#   2. sops secrets/vm-monitoring.yaml  ->  add  alerting/heartbeat_url: <ping URL>
#   3. Set homelab.monitoring.heartbeat.enable = true (vm-monitoring host).
#   4. make deploy-monitoring
#
# Until then no secret is referenced (sops-nix would fail activation on a
# missing key) and the timer is not installed.

let
  cfg = config.homelab.monitoring.heartbeat;
  urlFile = config.sops.secrets."alerting/heartbeat_url".path;

  heartbeat = pkgs.writeShellApplication {
    name = "monitoring-heartbeat";
    runtimeInputs = with pkgs; [ curl jq ];
    text = ''
      curl -fsS --max-time 10 http://127.0.0.1:9090/-/ready >/dev/null
      curl -fsS --max-time 10 http://127.0.0.1:9093/-/ready >/dev/null

      watchdogs="$(curl -fsS --max-time 10 \
        'http://127.0.0.1:9093/api/v2/alerts?active=true&silenced=false&inhibited=false&filter=alertname%3D%22Watchdog%22' |
        jq 'length')"
      if [ "$watchdogs" -lt 1 ]; then
        echo "Watchdog alert not present in Alertmanager; withholding heartbeat" >&2
        exit 1
      fi

      curl -fsS --max-time 10 --retry 3 --retry-delay 5 \
        "$(<"${urlFile}")" >/dev/null
      echo "heartbeat sent"
    '';
  };
in {
  options.homelab.monitoring.heartbeat.enable = lib.mkEnableOption
    "pinging an external dead-man's-switch URL while alerting is healthy";

  config = lib.mkIf cfg.enable {
    sops.secrets."alerting/heartbeat_url" = { };

    systemd.services.monitoring-heartbeat = {
      description = "Ping external heartbeat if the alerting pipeline is healthy";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe heartbeat;
      };
    };

    systemd.timers.monitoring-heartbeat = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "5min";
      };
    };
  };
}
