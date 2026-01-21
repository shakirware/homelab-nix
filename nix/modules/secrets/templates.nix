{ lib, config, ... }:

let
  cfg = config.homelab.secrets;

  mkTemplateContent = envAttrs:
    let
      lines = lib.mapAttrsToList
        (k: secretPath: "${k}=${config.sops.placeholder."${secretPath}"}")
        envAttrs;
    in (lib.concatStringsSep "\n" lines) + "\n";

  templates = cfg.envTemplates;

  allSecretPaths = lib.unique
    (lib.flatten (map (t: lib.attrValues t.env) (lib.attrValues templates)));

  secretsAttr = lib.listToAttrs (map (p: {
    name = p;
    value = { };
  }) allSecretPaths);

  templatesAttr =
    lib.mapAttrs (name: t: { content = mkTemplateContent t.env; }) templates;
in {
  options.homelab.secrets.envTemplates = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options.env = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Map of ENV_VAR -> sops secret path";
      };
    });
    default = { };
    description =
      "Declarative env-file templates generated via sops.templates.";
  };

  config = lib.mkIf (templates != { }) {
    sops.secrets = secretsAttr;
    sops.templates = templatesAttr;
  };

}
