{ config, lib, ... }:

let
  tz = "Europe/London";

  uid = toString config.homelab.ids.uid;
  gid = toString config.homelab.ids.mediaGid;

  port = 8901;

  appdataDir = "/srv/appdata/tuliprox";
  cfgDir = "${appdataDir}/config";
  dataDir = "${appdataDir}/data";
  backupDir = "${appdataDir}/backup";
  downloadsDir = "${appdataDir}/downloads";

  apiProxyConfig = ./config/api-proxy.yml;
  mainConfig = ./config/config.yml;
  sourceConfig = ./config/source.yml;

  gwIp = config.homelab.ips.gw;
in {
  homelab.secrets.envTemplates.tuliprox = {
    restartUnits = [ "podman-tuliprox.service" ];
    env = {
      TULIPROX_SERVER_NAME = "tuliprox/server_name";
      TULIPROX_SERVER_PROTOCOL = "tuliprox/server_protocol";
      TULIPROX_SERVER_HOST = "tuliprox/server_host";
      TULIPROX_SERVER_PORT = "tuliprox/server_port";
      TULIPROX_SERVER_TIMEZONE = "tuliprox/server_timezone";
      TULIPROX_SERVER_MESSAGE = "tuliprox/server_message";
      TULIPROX_TARGET = "tuliprox/target";
      TULIPROX_OUTPUT_USERNAME = "tuliprox/output_username";
      TULIPROX_OUTPUT_PASSWORD = "tuliprox/output_password";
      TULIPROX_PROXY_MODE = "tuliprox/proxy_mode";
      TULIPROX_SERVER_REF = "tuliprox/server_ref";
      TULIPROX_API_HOST = "tuliprox/api_host";
      TULIPROX_API_WEB_ROOT = "tuliprox/api_web_root";
      TULIPROX_WORKING_DIR = "tuliprox/working_dir";
      TULIPROX_LOG_LEVEL = "tuliprox/log_level";
      TULIPROX_TEMPLATE_NAME = "tuliprox/template_name";
      TULIPROX_TEMPLATE_VALUE = "tuliprox/template_value";
      TULIPROX_INPUT_NAME = "tuliprox/input_name";
      TULIPROX_INPUT_TYPE = "tuliprox/input_type";
      TULIPROX_SOURCE_URL = "tuliprox/source_url";
      TULIPROX_SOURCE_USERNAME = "tuliprox/source_username";
      TULIPROX_SOURCE_PASSWORD = "tuliprox/source_password";
      TULIPROX_PERSIST = "tuliprox/persist";
      TULIPROX_USER_AGENT = "tuliprox/user_agent";
      TULIPROX_EPG_URL = "tuliprox/epg_url";
      TULIPROX_TARGET_NAME = "tuliprox/target_name";
      TULIPROX_OUTPUT_TYPE = "tuliprox/output_type";
      TULIPROX_FILTER = "tuliprox/filter";
    };
  };

  systemd.tmpfiles.rules = lib.mkAfter [
    "d ${appdataDir}    2775 ${config.homelab.ids.user} media - -"
    "d ${cfgDir}        2775 ${config.homelab.ids.user} media - -"
    "d ${dataDir}       2775 ${config.homelab.ids.user} media - -"
    "d ${backupDir}     2775 ${config.homelab.ids.user} media - -"
    "d ${downloadsDir}  2775 ${config.homelab.ids.user} media - -"
  ];

  virtualisation.oci-containers.containers.tuliprox = {
    image = "ghcr.io/euzu/tuliprox:latest@sha256:44b08cb823bd161275f0cde4a3d833e52a4c3e655c7d4dbe8a9153e51ca8dca6";
    autoStart = true;

    cmd = [
      "/app/tuliprox"
      "-p"
      "/app/config"
      "-s"
      "-a"
      "/app/config/api-proxy.yml"
    ];

    ports = [ ];

    extraOptions = [
      "--network=container:gluetun"
      "--user=${uid}:${gid}"
      "--workdir=/app/data"
    ];

    environment = { TZ = tz; };

    environmentFiles = [ config.sops.templates.tuliprox.path ];

    volumes = [
      "${apiProxyConfig}:/app/config/api-proxy.yml:ro"
      "${mainConfig}:/app/config/config.yml:ro"
      "${sourceConfig}:/app/config/source.yml:ro"
      "${dataDir}:/app/data"
      "${backupDir}:/app/backup"
      "${downloadsDir}:/app/downloads"
    ];
  };

  systemd.services."podman-tuliprox" = {
    after = [ "podman-gluetun.service" "podman.service" ];
    requires = [ "podman-gluetun.service" "podman.service" ];
  };
}
