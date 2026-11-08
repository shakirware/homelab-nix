{ lib, ... }:

{
  options.homelab.nfsMount = {
    mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/srv/media";
      description = "Where the NFS export is mounted.";
    };

    export = lib.mkOption {
      type = lib.types.str;
      default = "/media";
      description = "Export path under the server's NFSv4 root.";
    };
  };
}
