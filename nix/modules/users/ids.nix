{ lib, ... }:

{
  options.homelab.ids = lib.mkOption {
    type = lib.types.submodule {
      options = {
        user = lib.mkOption {
          type = lib.types.str;
          default = "shakir";
          description = "Primary admin username.";
        };

        uid = lib.mkOption {
          type = lib.types.int;
          default = 1000;
          description = "Primary user UID (matches container PUID).";
        };

        mediaGid = lib.mkOption {
          type = lib.types.int;
          default = 1001;
          description = "Media group GID (matches container PGID).";
        };
      };
    };
    default = { };
    description = "Stable IDs for users/groups to keep permissions consistent.";
  };
}
