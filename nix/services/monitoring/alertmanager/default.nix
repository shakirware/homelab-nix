{ config, lib, pkgs, ... }:

let
  port = 9093;
  dataDir = "/srv/appdata/alertmanager";
  cfgName = "alertmanager.yml";

  baseDomain = config.homelab.baseDomain;
  publicHost = "alertmanager.${baseDomain}";
  publicUrl = "https://${publicHost}";

  telegramFailureNotifier = service: unit:
    pkgs.writeShellScript "telegram-${service}-failed" ''
      set -euo pipefail

      # Avoid alerts for transient failures during deploy/restart.
      ${pkgs.coreutils}/bin/sleep 60

      if ${pkgs.systemd}/bin/systemctl is-active --quiet ${unit}; then
        exit 0
      fi

      token="$(<${config.sops.secrets."alerting/telegram_bot_token".path})"
      chat_id="$(<${config.sops.secrets."alerting/telegram_chat_id".path})"

      ${pkgs.curl}/bin/curl \
        -fsS \
        --retry 3 \
        --max-time 15 \
        --data-urlencode "chat_id=$chat_id" \
        --data-urlencode "text=🔴 CRITICAL — ${service} failed on vm-monitoring" \
        "https://api.telegram.org/bot$token/sendMessage" \
        >/dev/null
    '';

  templatesDir = pkgs.runCommand "alertmanager-templates" { } ''
    mkdir -p $out
    cat > $out/telegram.tmpl <<'EOF'
      {{ define "telegram.message" }}
      <b>{{ if eq .Status "firing" }}🔴 FIRING{{ else }}✅ RESOLVED{{ end }}</b> — <b>{{ .CommonLabels.alertname }}</b>{{ if .CommonLabels.severity }} (<code>{{ .CommonLabels.severity }}</code>){{ end }}
      {{ if .CommonLabels.instance }}
      Host: <code>{{ .CommonLabels.instance }}</code>
      {{ end }}
      {{ if .CommonAnnotations.summary }}
      {{ .CommonAnnotations.summary }}
      {{ end }}
      {{ if .CommonAnnotations.description }}
      {{ .CommonAnnotations.description }}
      {{ end }}
      {{ if gt (len .Alerts) 1 }}

      Alerts ({{ len .Alerts }}):
      {{ range .Alerts }}• <code>{{ .Labels.instance }}</code>{{ with .Annotations.summary }} — {{ . }}{{ end }}
      {{ end }}{{ end }}

      <a href="{{ .ExternalURL }}">Alertmanager</a>{{ with (index .Alerts 0).GeneratorURL }} | <a href="{{ . }}">Source</a>{{ end }}
      {{ end }}
    EOF
  '';
in {
  sops.secrets."alerting/telegram_bot_token" = { };
  sops.secrets."alerting/telegram_chat_id" = { };

  sops.templates.${cfgName} = {
    content = ''
      global: {}

      templates:
        - /etc/alertmanager/templates/*.tmpl

      route:
        receiver: telegram
        group_by: [ "alertname", "instance" ]
        group_wait: 10s
        group_interval: 1m
        repeat_interval: 4h

        routes:
          - receiver: "null"
            matchers:
              - alertname="Watchdog"

          - receiver: "null"
            matchers:
              - severity="none"

      receivers:
        - name: "null"

        - name: telegram
          telegram_configs:
            - bot_token: "${config.sops.placeholder."alerting/telegram_bot_token"}"
              chat_id: ${config.sops.placeholder."alerting/telegram_chat_id"}
              send_resolved: true
              parse_mode: "HTML"
              message: '{{ template "telegram.message" . }}'
    '';
    owner = "root";
    group = "nogroup";
    mode = "0440";
  };

  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${dataDir} 0750 65534 65534 - -"
  ];

  virtualisation.oci-containers.containers.alertmanager = {
    image = "prom/alertmanager:v0.33.1";
    autoStart = true;

    user = "65534:65534";

    cmd = [
      "--config.file=/etc/alertmanager/alertmanager.yml"
      "--storage.path=/alertmanager"
      "--web.listen-address=0.0.0.0:${toString port}"
      "--web.external-url=${publicUrl}"
    ];

    volumes = [
      "${dataDir}:/alertmanager"
      "${config.sops.templates.${cfgName}.path}:/etc/alertmanager/alertmanager.yml:ro"
      "${templatesDir}:/etc/alertmanager/templates:ro"
    ];

    ports = [ ];

    extraOptions = [
      "--network=host"
    ];
  };

  systemd.services.monitoring-telegram-prometheus-failed = {
    description = "Send Telegram alert when Prometheus fails";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        telegramFailureNotifier "Prometheus" "podman-prometheus.service";
    };
  };

  systemd.services.monitoring-telegram-alertmanager-failed = {
    description = "Send Telegram alert when Alertmanager fails";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart =
        telegramFailureNotifier "Alertmanager" "podman-alertmanager.service";
    };
  };

  systemd.services.podman-prometheus.unitConfig.OnFailure =
    "monitoring-telegram-prometheus-failed.service";

  systemd.services.podman-alertmanager = {
    after = [ "podman.service" ];
    requires = [ "podman.service" ];

    unitConfig.OnFailure =
      "monitoring-telegram-alertmanager-failed.service";
  };
}
