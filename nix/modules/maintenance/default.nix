{ config, lib, pkgs, ... }:

# Weekly cleanup so old system generations and superseded container images
# don't pile up. Two weeks of generations stay available for rollback.
{
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
    persistent = true;
    randomizedDelaySec = "1h";
  };

  # Images only: `podman system prune` would also drop networks that a stopped
  # service needs on its next start.
  systemd.services.podman-image-prune = lib.mkIf config.virtualisation.podman.enable {
    description = "Remove container images no container uses";
    serviceConfig.Type = "oneshot";
    script = "${pkgs.podman}/bin/podman image prune --all --force";
  };

  systemd.timers.podman-image-prune = lib.mkIf config.virtualisation.podman.enable {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };
}
