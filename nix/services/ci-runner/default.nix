{ lib, pkgs, config, ... }:

# Ephemeral GitHub Actions runners for one repository (homelab.ciRunner): each takes one job,
# deregisters and exits, and systemd starts a fresh one with an empty work
# directory. Jobs run in an Ubuntu container (what setup-python, setup-node
# and the other actions expect) under rootless Docker owned by the "ci" user,
# so a job that abuses the Docker socket gets that user, not root. The
# registration PAT is root-only and never enters the container: the root
# ExecStartPre exchanges it for a one-hour registration token.

let
  cfg = config.homelab.ciRunner;
  inherit (cfg) repo labels;
  runners = lib.range 1 cfg.count;

  user = "ci";
  uid = 2000;
  home = "/var/lib/ci";
  name = n: "${cfg.namePrefix}-${toString n}"; # GitHub runner and Compose project name
  container = n: "gha-runner-${toString n}";
  # Same paths inside and outside the container. One tool cache per runner, so
  # two jobs never install into the same directory at once.
  workDir = n: "${home}/runner-work-${toString n}";
  toolCache = n: "${home}/toolcache-${toString n}";
  # The container's ~/.cache, kept between jobs: uv uses it by default on a
  # self-hosted runner, and pnpm is pointed at it, so neither downloads its
  # cache from GitHub. Per runner, like the tool cache.
  cacheDir = n: "${home}/cache-${toString n}";
  dockerSock = "/run/user/${toString uid}/docker.sock";
  dockerEnv = {
    DOCKER_HOST = "unix://${dockerSock}";
    XDG_RUNTIME_DIR = "/run/user/${toString uid}";
  };

  # Pinned by digest; bump both together (github.com/actions/runner releases).
  baseImage =
    "ghcr.io/actions/actions-runner:2.338.1@sha256:e275409999c37162649aa050ca573f03eab2eabcb3a1e7fcc47548de6b4f9690";

  # Reads the registration token from stdin so it is never in the
  # environment that jobs inherit.
  entrypoint = pkgs.writeText "ci-entrypoint" ''
    #!/bin/bash
    set -euo pipefail
    read -r token
    cd /home/runner
    ./config.sh --unattended --ephemeral --replace --disableupdate \
      --url "https://github.com/$RUNNER_REPO" --token "$token" \
      --name "$RUNNER_NAME" --labels "$RUNNER_LABELS" --work "$RUNNER_WORKDIR"
    unset token
    exec ./run.sh
  '';

  imageContext = pkgs.runCommand "gha-runner-image" { } ''
    mkdir -p $out
    cp ${entrypoint} $out/ci-entrypoint
    cat > $out/Dockerfile <<'EOF'
    FROM ${baseImage}
    # Excluded from the clean-up prunes below.
    LABEL homelab.ci.keep=true
    USER root
    # The tools ci.yml expects on ubuntu-latest that the runner image lacks.
    RUN apt-get update \
     && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
          build-essential make git curl ca-certificates jq unzip zstd xz-utils \
          shellcheck python3 python3-venv lsb-release gh openssh-client \
     && rm -rf /var/lib/apt/lists/*
    # The image has buildx but not Compose; pinned by checksum.
    RUN curl -fsSLo /usr/local/lib/docker/cli-plugins/docker-compose \
          https://github.com/docker/compose/releases/download/v5.6.0/docker-compose-linux-x86_64 \
     && echo "40343e21ca777173e69cff5dbafeb37c6f81f3b0d57d9e597f036e95eb63e76a  /usr/local/lib/docker/cli-plugins/docker-compose" | sha256sum -c - \
     && chmod 0755 /usr/local/lib/docker/cli-plugins/docker-compose
    # Jobs run as container root; workflows written for ubuntu-latest still
    # call sudo. The image's sudoers has only the %sudo rule (no includedir).
    RUN usermod -aG sudo root
    COPY --chmod=0755 ci-entrypoint /usr/local/bin/ci-entrypoint
    EOF
  '';
  imageTag = "local/gha-runner:${
      builtins.substring 0 12
      (builtins.hashString "sha256" (toString imageContext))
    }";

  # docker_28, nixpkgs' default here, is end-of-life and marked insecure.
  dockerPkg = pkgs.docker_29;
  docker = "${dockerPkg}/bin/docker";

  ensureImage = pkgs.writeShellScript "github-runner-ensure-image" ''
    set -euo pipefail
    for _ in $(seq 60); do [ -S ${dockerSock} ] && break; sleep 2; done
    ${docker} image inspect ${imageTag} >/dev/null 2>&1 ||
      ${docker} build -t ${imageTag} ${imageContext}
  '';

  # Root: reset the work directory (jobs leave files owned by container
  # sub-UIDs that "ci" cannot delete) and mint a registration token.
  prepare = n:
    pkgs.writeShellScript "github-runner-${toString n}-prepare" ''
      set -euo pipefail
      PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq ]}
      rm -rf --one-file-system ${workDir n}
      for dir in ${workDir n} ${toolCache n} ${cacheDir n}; do
        install -d -o ${user} -g ${user} -m 0750 "$dir"
      done

      pat=$(cat ${config.sops.secrets.github_runner_pat.path})
      case "$pat" in
        github_pat_*) ;;
        *) echo "github_runner_pat in secrets/${config.networking.hostName}.yaml is not a fine-grained PAT" >&2; exit 1 ;;
      esac
      # Via curl --config on stdin, so the PAT is never in a process argument.
      printf 'header = "Authorization: Bearer %s"\n' "$pat" |
        curl -fsS --config - -X POST \
          -H "Accept: application/vnd.github+json" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          https://api.github.com/repos/${repo}/actions/runners/registration-token |
        jq -er .token > /run/github-runner-${toString n}/token
      chown ${user}: /run/github-runner-${toString n}/token
      chmod 0400 /run/github-runner-${toString n}/token
    '';

  start = n:
    pkgs.writeShellScript "github-runner-${toString n}-start" ''
      set -euo pipefail
      ${docker} rm -f ${container n} >/dev/null 2>&1 || true
      # Whatever a cancelled job left running (its test database keeps
      # restarting until removed).
      project="label=com.docker.compose.project=${name n}"
      ${docker} ps -aq --filter "$project" | xargs -r ${docker} rm -fv
      ${docker} network ls -q --filter "$project" | xargs -r ${docker} network rm
      ${ensureImage}
      exec 3</run/github-runner-${toString n}/token
      rm -f /run/github-runner-${toString n}/token
      # Container root is "ci" on the host (rootless), so the bind-mounted work
      # directory is writable and job bind mounts resolve to the same paths.
      # RUNNER_MANUALLY_TRAP_SIG makes run.sh pass SIGTERM to the listener, so a
      # stop deregisters cleanly instead of leaving a stale session behind.
      # COMPOSE_PROJECT_NAME keeps two runners' test stacks apart.
      exec ${docker} run --rm -i --init --name ${container n} \
        --user 0 -e RUNNER_ALLOW_RUNASROOT=1 -e RUNNER_MANUALLY_TRAP_SIG=1 \
        -e RUNNER_REPO=${repo} -e RUNNER_NAME=${name n} \
        -e RUNNER_LABELS=${labels} -e RUNNER_WORKDIR=${workDir n} \
        -e RUNNER_TOOL_CACHE=${toolCache n} \
        -e AGENT_TOOLSDIRECTORY=${toolCache n} \
        -e COMPOSE_PROJECT_NAME=${name n} \
        -e npm_config_store_dir=/root/.cache/pnpm-store \
        -e DOCKER_HOST=unix:///var/run/docker.sock \
        -v ${dockerSock}:/var/run/docker.sock \
        -v ${workDir n}:${workDir n} -v ${toolCache n}:${toolCache n} \
        -v ${cacheDir n}:/root/.cache \
        --entrypoint /usr/local/bin/ci-entrypoint ${imageTag} <&3
    '';

  runnerService = n: {
    description = "GitHub Actions runner ${name n} for ${repo} (ephemeral)";
    wantedBy = [ "multi-user.target" ];
    requires = [ "github-runner-image.service" ];
    after = [ "github-runner-image.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = dockerEnv;
    # A job may run for its 30-minute timeout; a redeploy waits for it.
    restartIfChanged = false;
    unitConfig = {
      # A bad PAT fails fast instead of retrying forever.
      StartLimitIntervalSec = "10min";
      StartLimitBurst = 20;
    };
    serviceConfig = {
      User = user;
      Group = user;
      RuntimeDirectory = "github-runner-${toString n}";
      RuntimeDirectoryMode = "0700";
      ExecStartPre = "+${prepare n}";
      ExecStart = start n;
      ExecStop = "${docker} stop -t 30 ${container n}";
      SuccessExitStatus = 143; # a clean stop is SIGTERM
      # Each job ends with a clean exit; start the next registration.
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # A job is running when any runner has spawned its worker.
  busy = lib.concatMapStringsSep " || "
    (n: "${docker} exec ${container n} pgrep -f Runner.Worker >/dev/null 2>&1")
    runners;

  gc = pkgs.writeShellScript "ci-docker-gc" ''
    set -uo pipefail
    if ${busy}; then echo "job running; skipping"; exit 0; fi
    ${docker} container prune -f --filter until=24h
    ${docker} image prune -af --filter until=168h --filter label!=homelab.ci.keep=true
    # Runner images from earlier deploys (the label only protects the current one).
    ${docker} images --filter label=homelab.ci.keep=true --format '{{.Repository}}:{{.Tag}}' |
      grep -vxF ${imageTag} | xargs -r ${docker} rmi
    ${docker} builder prune -af --filter until=168h
    ${docker} volume prune -af
    # Builders setup-buildx-action left behind when a job was cancelled.
    ${docker} ps -aq --filter name=buildx_buildkit_ | xargs -r ${docker} rm -fv
    ${docker} volume ls -q --filter name=buildx_buildkit_ | xargs -r ${docker} volume rm
    ${docker} network prune -f
    for dir in ${home}/toolcache-* ${home}/cache-*; do
      if [ "$(du -sm "$dir" | cut -f1)" -gt 5120 ]; then
        echo "$dir over 5 GiB; clearing"
        find "$dir" -mindepth 1 -delete
      fi
    done
    df -h /
  '';

  # Every 10 minutes: above 75% use, drop everything unused at once.
  diskGuard = pkgs.writeShellScript "ci-disk-guard" ''
    set -uo pipefail
    used=$(df --output=pcent / | tail -1 | tr -dc 0-9)
    [ "$used" -lt 75 ] && exit 0
    if ${busy}; then echo "disk at $used% but a job is running"; exit 0; fi
    echo "disk at $used%; pruning all unused Docker data"
    ${docker} system prune -af --volumes --filter label!=homelab.ci.keep=true
    ${docker} builder prune -af
    df -h /
  '';
in {
  options.homelab.ciRunner = {
    repo = lib.mkOption {
      type = lib.types.str;
      description = "owner/name of the repository the runners register to.";
    };
    labels = lib.mkOption {
      type = lib.types.str;
      description = "Comma-separated runner labels that workflows target.";
    };
    count = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Parallel runners, each taking one job at a time.";
    };
    namePrefix = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Runner names are <prefix>-<n>.";
    };
    memoryHigh = lib.mkOption {
      type = lib.types.str;
      description = "MemoryHigh for everything the ci user runs.";
    };
    memoryMax = lib.mkOption {
      type = lib.types.str;
      description = "MemoryMax for everything the ci user runs.";
    };
  };

  config = {
    users.groups.${user}.gid = uid;
    users.users.${user} = {
      inherit uid home;
      group = user;
      isNormalUser = true; # gives the sub-UID/GID ranges rootless Docker needs
      createHome = true;
      linger = true; # its user manager (and Docker) start at boot
      shell = "${pkgs.shadow}/bin/nologin";
    };

    virtualisation.docker.rootless = {
      enable = true;
      package = dockerPkg;
      daemon.settings = {
        log-driver = "json-file";
        log-opts = {
          max-size = "10m";
          max-file = "3";
        };
        features.buildkit = true;
        builder.gc = {
          enabled = true;
          defaultKeepStorage = "15GB";
        };
      };
    };
    # The module starts a daemon for every user; only "ci" needs one.
    systemd.user.services.docker.unitConfig.ConditionUser = lib.mkForce user;

    # Everything "ci" runs (Docker, the runners, job containers) shares one
    # slice: a runaway build cannot starve sshd, node-exporter or the journal.
    systemd.slices."user-${toString uid}" = {
      overrideStrategy = "asDropin";
      sliceConfig = {
        MemoryHigh = cfg.memoryHigh;
        MemoryMax = cfg.memoryMax;
        CPUWeight = 50;
        IOWeight = 50;
        TasksMax = 8192;
      };
    };

    sops.secrets.github_runner_pat = { }; # root:root 0400

    systemd.services = {
      # Lets the slice above limit CPU and I/O as well as memory.
      "user@".serviceConfig.Delegate = "cpu cpuset io memory pids";

      github-runner-image = {
        description = "Build the GitHub Actions runner image";
        requires = [ "user@${toString uid}.service" ];
        after = [ "user@${toString uid}.service" "network-online.target" ];
        wants = [ "network-online.target" ];
        environment = dockerEnv;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = user;
          TimeoutStartSec = "20min";
          ExecStart = ensureImage;
        };
      };

      ci-docker-gc = {
        description = "Remove old CI images, build cache and volumes";
        environment = dockerEnv;
        serviceConfig = {
          Type = "oneshot";
          User = user;
          ExecStart = gc;
        };
      };

      ci-disk-guard = {
        description = "Prune CI Docker data when the disk is nearly full";
        environment = dockerEnv;
        serviceConfig = {
          Type = "oneshot";
          User = user;
          ExecStart = diskGuard;
        };
      };
    } // lib.listToAttrs
      (map (n: lib.nameValuePair "github-runner-${toString n}" (runnerService n))
        runners);

    systemd.timers.ci-docker-gc = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "04:00";
        Persistent = true;
      };
    };
    systemd.timers.ci-disk-guard = {
      wantedBy = [ "timers.target" ];
      timerConfig.OnUnitActiveSec = "10min";
      timerConfig.OnBootSec = "10min";
    };
  };
}
