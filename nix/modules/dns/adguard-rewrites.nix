{ lib, config, ... }:

{
  options.homelab.adguard.rewrites = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        domain = lib.mkOption { type = lib.types.str; };
        answer = lib.mkOption { type = lib.types.str; };
      };
    });
    default = [ ];
    description = "AdGuard Home DNS rewrites derived from homelab.domains.";
  };

  config.homelab.adguard.rewrites = lib.mkDefault
    (lib.mapAttrsToList (domain: answer: { inherit domain answer; })
      config.homelab.domains);
}
