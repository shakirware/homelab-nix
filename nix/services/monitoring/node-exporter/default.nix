{ config, lib, ... }:

let
  port = 9100;
  promIp = config.homelab.ips.monitoring;
in {
  services.prometheus.exporters.node = {
    enable = true;
    port = port;
    listenAddress = "0.0.0.0";
    enabledCollectors = [ "systemd" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  networking.nftables.tables."node-exporter-guard" = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -50; policy accept;
        tcp dport ${toString port} jump node_exporter_guard
      }

      chain node_exporter_guard {
        ct state established,related accept
        iifname "lo" accept
        ip saddr ${promIp} accept
        drop
      }
    '';
  };
}
