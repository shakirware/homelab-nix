{ lib, config, ... }:

let
  host = config.networking.hostName;

  secretsDir = ../../../secrets;

  hostSecretsPathStr = "${toString secretsDir}/${host}.yaml";
  hostSecretsPath = builtins.toPath hostSecretsPathStr;

  exists = builtins.pathExists hostSecretsPath;
in {
  options.homelab.secrets.enableHostFile = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description =
      "If true and secrets/<hostname>.yaml exists, use it as sops.defaultSopsFile.";
  };

  config = lib.mkIf (config.homelab.secrets.enableHostFile && exists) {
    sops.defaultSopsFile = lib.mkDefault hostSecretsPath;
  };
}
