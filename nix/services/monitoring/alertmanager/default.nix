{ config, lib, pkgs, ... }:

let
  port = 9093;
  dataDir = "/srv/appdata/alertmanager";
  cfgName = "alertmanager.yml";
in {
  sops.secrets."alerting/telegram_bot_token" = { };
  sops.secrets."alerting/telegram_chat_id" = { };

  sops.templates.${cfgName} = {
    content = ''
      global: {}

      route:
        receiver: telegram
        group_by: [ "alertname", "instance" ]
        group_wait: 10s
        group_interval: 1m
        repeat_interval: 4h

      receivers:
        - name: telegram
          telegram_configs:
            - bot_token: "${
              config.sops.placeholder."alerting/telegram_bot_token"
            }"
              chat_id: ${config.sops.placeholder."alerting/telegram_chat_id"}
              send_resolved: true
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
    ];

    volumes = [
      "${dataDir}:/alertmanager"
      "${
        config.sops.templates.${cfgName}.path
      }:/etc/alertmanager/alertmanager.yml:ro"
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
