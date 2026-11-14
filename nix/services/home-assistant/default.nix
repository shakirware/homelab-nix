{
  config,
  lib,
  pkgs,
  home,
  ...
}:

let
  port = 8123;

  cfgRoot = "/srv/appdata/home-assistant";
  cfgDir = "${cfgRoot}/config";
  mediaDir = "${cfgRoot}/media";
  backupDir = "${cfgRoot}/backups";
  packageDir = "${cfgDir}/packages";

  secretsTemplateName = "home-assistant-secrets.yaml";
  secretsFile = config.sops.templates.${secretsTemplateName}.path;

  homeAssistantImage = "ghcr.io/home-assistant/home-assistant:2026.10.2@sha256:33afb0659d786213264c2211f8d91c5fe87461c56eba6a3a546eb05fc71e89f4";

  homeAssistantHost = "homeassistant.${config.homelab.baseDomain}";
  gwIp = config.homelab.ips.gw;

  configuration = pkgs.writeText "configuration.yaml" ''
    default_config:

    automation: !include automations.yaml
    script: !include scripts.yaml
    scene: !include scenes.yaml

    homeassistant:
      name: Home
      latitude: !secret home_latitude
      longitude: !secret home_longitude
      country: GB
      elevation: 0
      unit_system: metric
      currency: GBP
      time_zone: ${config.time.timeZone}
      external_url: "https://${homeAssistantHost}"
      internal_url: "https://${homeAssistantHost}"
      packages: !include_dir_named packages

    http:
      use_x_forwarded_for: true
      trusted_proxies:
        - ${gwIp}

  '';

  validateConfig = pkgs.writeShellScript "home-assistant-validate-config" ''
    set -euo pipefail

    validation_root="$(${pkgs.coreutils}/bin/mktemp -d /run/home-assistant-config-check.XXXXXX)"
    trap '${pkgs.coreutils}/bin/rm -rf "$validation_root"' EXIT

    ${pkgs.coreutils}/bin/install -d -m 0700 \
      "$validation_root/config/packages" "$validation_root/media"
    ${pkgs.coreutils}/bin/install -m 0600 \
      ${configuration} "$validation_root/config/configuration.yaml"
    ${pkgs.coreutils}/bin/touch \
      "$validation_root/config/automations.yaml" \
      "$validation_root/config/scripts.yaml" \
      "$validation_root/config/scenes.yaml"

    ${pkgs.coreutils}/bin/install -m 0600 \
      ${./config/packages/home_comfort_alerts.yaml} \
      "$validation_root/config/packages/home_comfort_alerts.yaml"
    ${pkgs.coreutils}/bin/install -m 0600 \
      ${./config/packages/bin_collection_alerts.yaml} \
      "$validation_root/config/packages/bin_collection_alerts.yaml"
    ${pkgs.coreutils}/bin/install -m 0600 \
      ${./config/packages/washing_guard.yaml} \
      "$validation_root/config/packages/washing_guard.yaml"

    ${pkgs.coreutils}/bin/timeout 480 \
      ${pkgs.podman}/bin/podman run --rm --pull=missing --network=none \
        --name home-assistant-config-check \
        --entrypoint python \
        -v "$validation_root/config:/config:ro" \
        -v ${secretsFile}:/config/secrets.yaml:ro \
        -v "$validation_root/media:/media:ro" \
        ${homeAssistantImage} \
        -m homeassistant --script check_config -c /config
  '';
in
{
  sops.secrets."home-assistant/latitude" = { };
  sops.secrets."home-assistant/longitude" = { };

  sops.templates.${secretsTemplateName} = {
    content = ''
      home_latitude: ${config.sops.placeholder."home-assistant/latitude"}
      home_longitude: ${config.sops.placeholder."home-assistant/longitude"}
    '';
    owner = "root";
    group = "root";
    mode = "0400";
    restartUnits = [ "podman-home-assistant.service" ];
  };

  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${cfgRoot} 2775 ${config.homelab.ids.user} media - -"
    # config/.storage and backups hold integration credentials.
    "d ${cfgDir} 2770 ${config.homelab.ids.user} media - -"
    "d ${mediaDir} 2775 ${config.homelab.ids.user} media - -"
    "d ${backupDir} 2770 ${config.homelab.ids.user} media - -"
    "d ${packageDir} 2775 ${config.homelab.ids.user} media - -"
  ];

  # Activation runs before systemd stops or replaces the production container.
  # The validator uses only declarative files and the runtime SOPS template, so
  # production state (including .storage) is never mounted or modified.
  system.activationScripts.home-assistant-config-check = {
    deps = [ "setupSecrets" ];
    text = ''
      ${validateConfig}
    '';
  };

  systemd.services.home-assistant-config = {
    description = "Seed Home Assistant config";
    wantedBy = [ "multi-user.target" ];
    before = [ "podman-home-assistant.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    path = [ pkgs.coreutils pkgs.findutils ];

    script = ''
      set -euo pipefail

      install -d -m 2770 -o ${config.homelab.ids.user} -g media \
        ${cfgDir} ${backupDir}
      install -d -m 2775 -o ${config.homelab.ids.user} -g media \
        ${packageDir} ${mediaDir}

      install -m 0664 -o ${config.homelab.ids.user} -g media \
        ${configuration} ${cfgDir}/configuration.yaml

      touch ${cfgDir}/automations.yaml ${cfgDir}/scripts.yaml ${cfgDir}/scenes.yaml
      chown ${config.homelab.ids.user}:media \
        ${cfgDir}/automations.yaml ${cfgDir}/scripts.yaml ${cfgDir}/scenes.yaml
      chmod 0664 \
        ${cfgDir}/automations.yaml ${cfgDir}/scripts.yaml ${cfgDir}/scenes.yaml

      find ${packageDir} -maxdepth 1 -type f -name '*.yaml' -delete

      install -m 0664 -o ${config.homelab.ids.user} -g media \
        ${./config/packages/home_comfort_alerts.yaml} ${packageDir}/home_comfort_alerts.yaml

      install -m 0664 -o ${config.homelab.ids.user} -g media \
        ${./config/packages/bin_collection_alerts.yaml} ${packageDir}/bin_collection_alerts.yaml

      install -m 0664 -o ${config.homelab.ids.user} -g media \
        ${./config/packages/washing_guard.yaml} ${packageDir}/washing_guard.yaml

    '';
  };

  virtualisation.oci-containers.containers."home-assistant" = {
    image = homeAssistantImage;
    environment = {
      TZ = config.time.timeZone;
    };

    volumes = [
      "${cfgDir}:/config"
      "${secretsFile}:/config/secrets.yaml:ro"
      "${mediaDir}:/media"
      "${backupDir}:/backup"
      "/etc/localtime:/etc/localtime:ro"
    ];

    extraOptions = [
      "--network=host"
      # Without an in-network nameserver, the dhcp integration's network scan
      # (aiodiscover) sends PTR lookups to the default gateway, which does not
      # resolve.
      "--dns=${gwIp}"
    ];
  };

  systemd.services.podman-home-assistant = {
    after = [
      "home-assistant-config.service"
      "network-online.target"
    ];
    requires = [ "home-assistant-config.service" ];
    wants = [ "network-online.target" ];
    restartTriggers = [
      configuration
      ./config/packages/home_comfort_alerts.yaml
      ./config/packages/bin_collection_alerts.yaml
      ./config/packages/washing_guard.yaml
    ];
  };

  networking.firewall.allowedTCPPorts = [ port ];

  homelab.firewall.restrict.${toString port} = [ gwIp home.cidr ];

  homelab.backup = {
    paths = [ cfgDir mediaDir backupDir ];
    exclude = [
      "${cfgDir}/home-assistant_v2.db"
      "${cfgDir}/home-assistant.log*"
      "${cfgDir}/.cache"
    ];
    sqlite = [ "${cfgDir}/home-assistant_v2.db" ];
  };
}
