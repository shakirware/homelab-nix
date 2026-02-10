{ config, lib, pkgs, ... }:

let
  port = 9093;
  dataDir = "/srv/appdata/alertmanager";
  cfgName = "alertmanager.yml";

  baseDomain = config.homelab.baseDomain;
  publicHost = "alertmanager.${baseDomain}";
  publicUrl = "https://${publicHost}";

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
            - bot_token: "${
              config.sops.placeholder."alerting/telegram_bot_token"
            }"
              chat_id: "${config.sops.placeholder."alerting/telegram_chat_id"}"
              send_resolved: true
              parse_mode: "HTML"
              message: '{{ template "telegram.message" . }}'
    '';
    owner = "root";
    group = "nogroup";
    mode = "0440";
  };

  systemd.tmpfiles.rules = lib.mkAfter [ "d ${dataDir} 0750 65534 65534 - -" ];

  virtualisation.oci-containers.containers.alertmanager = {
    image = "prom/alertmanager:v0.27.0";
    autoStart = true;

    cmd = [
      "--config.file=/etc/alertmanager/alertmanager.yml"
      "--storage.path=/alertmanager"
      "--web.listen-address=0.0.0.0:${toString port}"
      "--web.external-url=${publicUrl}"
    ];

    volumes = [
      "${dataDir}:/alertmanager"
      "${
        config.sops.templates.${cfgName}.path
      }:/etc/alertmanager/alertmanager.yml:ro"
      "${templatesDir}:/etc/alertmanager/templates:ro"
    ];

    ports = [ ];

    extraOptions =
      [ "--network=host" "--user=65534:65534" "--name=alertmanager" ];
  };

  systemd.services.podman-alertmanager = {
    after = [ "podman.service" ];
    requires = [ "podman.service" ];
  };
}
