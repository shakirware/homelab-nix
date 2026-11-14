{ config, lib, pkgs, ... }:

let
  baseDomain = config.homelab.baseDomain;

  port = 9090;
  dataDir = "/srv/appdata/prometheus";

  nodePort = 9100;

  publicHost = "prometheus.${baseDomain}";
  publicUrl = "https://${publicHost}";

  # Metric contract for backup jobs (node_exporter textfile written after
  # each run by nix/modules/backup/metrics.nix and restic-offsite):
  #   homelab_backup_last_success_timestamp_seconds{backup="<name>"}
  #   homelab_backup_last_run_success{backup="<name>"}   1 = ok, 0 = failed
  #   homelab_backup_max_age_seconds{backup="<name>"}    schedule + slack
  #   homelab_backup_repo_bytes{repo="local-<host>"|"b2-<host>"}
  backupAlertsEnabled = true;

  prometheusYaml = import ./scrape-config.nix {
    inherit config lib pkgs port nodePort;
  };

  rulesDir = pkgs.runCommand "prometheus-rules" { } ''
    mkdir -p $out
    for f in ${./rules}/*.yml; do
      substitute "$f" "$out/$(basename "$f")" \
        --subst-var-by baseDomain ${lib.escapeShellArg baseDomain} \
        --subst-var-by nodePort ${toString nodePort}
    done
    if grep -n '@[A-Za-z_]*@' $out/*.yml; then
      echo "unsubstituted placeholder in a rule file" >&2
      exit 1
    fi
    ${lib.optionalString (!backupAlertsEnabled) "mv $out/backups.yml $out/backups.yml.disabled"}
  '';

  configCheck = pkgs.runCommand "prometheus-config-check" {
    nativeBuildInputs = [ pkgs.prometheus.cli ];
  } ''
    promtool check rules ${rulesDir}/*.yml
    sed 's#/etc/prometheus/rules/#${rulesDir}/#' ${prometheusYaml} > prometheus.yml
    promtool check config prometheus.yml
    touch $out
  '';
in {
  system.checks = [ configCheck ];

  systemd.tmpfiles.rules = lib.mkAfter [ "d ${dataDir} 0750 65534 65534 - -" ];

  virtualisation.oci-containers.containers.prometheus = {
    image = "prom/prometheus:v3.15.1@sha256:fa3302279710be2f21a8301ec17a8b4f2301fd829bd113839b3b6b02b6f191a2";
    cmd = [
      "--config.file=/etc/prometheus/prometheus.yml"
      "--storage.tsdb.path=/prometheus"
      "--storage.tsdb.retention.time=30d"
      "--web.enable-lifecycle"
      "--web.external-url=${publicUrl}"
    ];

    volumes = [
      "${dataDir}:/prometheus"
      "${prometheusYaml}:/etc/prometheus/prometheus.yml:ro"
      "${rulesDir}:/etc/prometheus/rules:ro"
    ];

    ports = [ ];
    extraOptions = [ "--network=host" "--name=prometheus" ];
  };

  systemd.services.podman-prometheus = {
    after = [ "podman.service" ];
    requires = [ "podman.service" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  homelab.firewall.restrict.${toString port} = [ config.homelab.ips.gw ];
}
