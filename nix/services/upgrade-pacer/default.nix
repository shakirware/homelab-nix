{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.upgradePacer;

  pacer = pkgs.writers.writePython3Bin "homelab-upgrade-pacer" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./pacer.py);
in {
  options.homelab.upgradePacer = {
    apply = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Move titles and start searches; when false, only log what would happen.";
    };
    moviesPerRun = lib.mkOption {
      type = lib.types.int;
      default = 3;
    };
    seasonsPerRun = lib.mkOption {
      type = lib.types.int;
      default = 2;
    };
    interval = lib.mkOption {
      type = lib.types.str;
      default = "2h";
    };
    maxQueue = lib.mkOption {
      type = lib.types.int;
      default = 6;
    };
  };

  config = {
    environment.systemPackages = [ pacer ];

    systemd.services.homelab-upgrade-pacer = {
      description = "Move a few library titles at a time onto the upgrade profiles and search them";
      after = [ "podman-radarr.service" "podman-sonarr.service" ];
      environment = {
        PACER_APPLY = if cfg.apply then "1" else "0";
        PACER_MOVIES_PER_RUN = toString cfg.moviesPerRun;
        PACER_SEASONS_PER_RUN = toString cfg.seasonsPerRun;
        PACER_MAX_QUEUE = toString cfg.maxQueue;
        PACER_MEDIA_PATH = "/srv/media";
        PACER_DOWNLOADS_PATH = "/srv/downloads";
        PACER_STATE_PATH = "/var/lib/homelab-upgrade-pacer/state.json";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe pacer;
        TimeoutStartSec = "10min";
        StateDirectory = "homelab-upgrade-pacer";
      };
    };

    systemd.timers.homelab-upgrade-pacer = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "30min";
        OnUnitActiveSec = cfg.interval;
        RandomizedDelaySec = "10min";
      };
    };
  };
}
