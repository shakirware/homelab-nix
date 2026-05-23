{ config, lib, pkgs, home, ... }:

let
  tz = "Europe/London";
  port = 8123;

  cfgRoot = "/srv/appdata/home-assistant";
  cfgDir = "${cfgRoot}/config";
  mediaDir = "${cfgRoot}/media";
  backupDir = "${cfgRoot}/backups";
  packageDir = "${cfgDir}/packages";
  snapshotDir = "${mediaDir}/doorbell";

  homeAssistantHost = "homeassistant.${config.homelab.baseDomain}";
  gwIp = config.homelab.ips.gw;

  configuration = pkgs.writeText "configuration.yaml" ''
    default_config:

    automation: !include automations.yaml
    script: !include scripts.yaml
    scene: !include scenes.yaml

    homeassistant:
      name: Home
      country: GB
      elevation: 0
      unit_system: metric
      currency: GBP
      time_zone: ${tz}
      external_url: "https://${homeAssistantHost}"
      internal_url: "https://${homeAssistantHost}"
      packages: !include_dir_named packages
      allowlist_external_dirs:
        - /media

    http:
      use_x_forwarded_for: true
      trusted_proxies:
        - ${gwIp}

    shell_command:
      extract_front_door_recording_frames: >-
        sh -c 'set -eu;
        rm -f /media/doorbell/front_door_frame_*.jpg;
        ffmpeg -hide_banner -loglevel error -y
        -i "$1"
        -vf "fps=1/5,scale=1280:-1"
        -frames:v 4
        -q:v 2
        /media/doorbell/front_door_frame_%02d.jpg;
        test -s /media/doorbell/front_door_frame_01.jpg;
        for n in 02 03 04; do
          test -s /media/doorbell/front_door_frame_$n.jpg || cp /media/doorbell/front_door_frame_01.jpg /media/doorbell/front_door_frame_$n.jpg;
        done'
        _ "{{ video_url }}"

      extract_downstairs_recording_frames: >-
        sh -c 'set -eu;
        rm -f /media/doorbell/downstairs_frame_*.jpg;
        ffmpeg -hide_banner -loglevel error -y
        -i "$1"
        -vf "fps=1/5,scale=1280:-1"
        -frames:v 4
        -q:v 2
        /media/doorbell/downstairs_frame_%02d.jpg;
        test -s /media/doorbell/downstairs_frame_01.jpg;
        for n in 02 03 04; do
          test -s /media/doorbell/downstairs_frame_$n.jpg || cp /media/doorbell/downstairs_frame_01.jpg /media/doorbell/downstairs_frame_$n.jpg;
        done'
        _ "{{ video_url }}"
  '';
in {
  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${cfgRoot} 2775 ${config.homelab.ids.user} media - -"
    "d ${cfgDir} 2775 ${config.homelab.ids.user} media - -"
    "d ${mediaDir} 2775 ${config.homelab.ids.user} media - -"
    "d ${backupDir} 2775 ${config.homelab.ids.user} media - -"
    "d ${packageDir} 2775 ${config.homelab.ids.user} media - -"
    "d ${snapshotDir} 2775 ${config.homelab.ids.user} media - -"
  ];

  systemd.services.home-assistant-config = {
    description = "Seed Home Assistant config";
    wantedBy = [ "multi-user.target" ];
    before = [ "podman-home-assistant.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = [ pkgs.coreutils ];

    script = ''
      set -euo pipefail

      install -d -m 2775 -o ${config.homelab.ids.user} -g media \
        ${cfgDir} ${packageDir} ${snapshotDir} ${mediaDir} ${backupDir}

      install -m 0664 -o ${config.homelab.ids.user} -g media \
        ${configuration} ${cfgDir}/configuration.yaml

      touch ${cfgDir}/automations.yaml ${cfgDir}/scripts.yaml ${cfgDir}/scenes.yaml
      chown ${config.homelab.ids.user}:media \
        ${cfgDir}/automations.yaml ${cfgDir}/scripts.yaml ${cfgDir}/scenes.yaml
      chmod 0664 \
        ${cfgDir}/automations.yaml ${cfgDir}/scripts.yaml ${cfgDir}/scenes.yaml

      install -m 0664 -o ${config.homelab.ids.user} -g media \
        ${./config/packages/ring_ai_doorbell.yaml} ${packageDir}/ring_ai_doorbell.yaml

      install -m 0664 -o ${config.homelab.ids.user} -g media \
        ${./config/packages/home_comfort_alerts.yaml} ${packageDir}/home_comfort_alerts.yaml

      install -m 0664 -o ${config.homelab.ids.user} -g media \
        ${./config/packages/d10_robot_vacuum.yaml} ${packageDir}/d10_robot_vacuum.yaml

      install -m 0664 -o ${config.homelab.ids.user} -g media \
        ${./config/packages/bin_collection_alerts.yaml} ${packageDir}/bin_collection_alerts.yaml
    '';
  };

  virtualisation.oci-containers.containers."home-assistant" = {
    image = "ghcr.io/home-assistant/home-assistant:stable";
    autoStart = true;

    environment = {
      TZ = tz;
    };

    volumes = [
      "${cfgDir}:/config"
      "${mediaDir}:/media"
      "${backupDir}:/backup"
      "/etc/localtime:/etc/localtime:ro"
    ];

    extraOptions = [ "--network=host" ];
  };

  systemd.services.podman-home-assistant = {
    after = [ "home-assistant-config.service" "network-online.target" ];
    requires = [ "home-assistant-config.service" ];
    wants = [ "network-online.target" ];
  };

  networking.firewall.allowedTCPPorts = lib.mkAfter [ port ];

  networking.nftables.tables."home-assistant-backend-guard" = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority -50; policy accept;
        tcp dport ${toString port} jump home_assistant_guard
      }

      chain home_assistant_guard {
        ct state established,related accept
        iifname "lo" accept
        iifname "tailscale0" accept
        ip saddr ${gwIp} accept
        ip saddr ${home.cidr} accept
        drop
      }
    '';
  };
}
