{ config, lib, ... }:

let
  port = 9100;

  textfileDir = "/var/lib/prometheus-node-exporter-textfile";
  promIp = config.homelab.ips.monitoring;
in {
  services.prometheus.exporters.node = {
    enable = true;
    port = port;
    listenAddress = "0.0.0.0";
    enabledCollectors = [ "systemd" ];
    extraFlags = [
      "--collector.textfile.directory=${textfileDir}"
      "--collector.systemd.enable-restarts-metrics"
    ];
  };

  systemd.tmpfiles.rules = lib.mkAfter [ "d ${textfileDir} 0755 root root - -" ];

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  homelab.firewall.restrict.${toString port} = [ promIp ];
}
