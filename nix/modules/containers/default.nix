{ config, lib, ... }:

let
  cfg = config.homelab.containers;

  containerType = lib.types.submodule {
    options = {
      publish = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        default = { };
        example = lib.literalExpression
          ''{ "7878" = [ config.homelab.ips.gw ]; }'';
        description = ''
          Ports published on all host addresses (same port inside the
          container), each with the sources allowed to reach it through
          `homelab.firewall.restrict`.
        '';
      };

      media = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Start only once /srv/media is mounted.";
      };

      vpn = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Share gluetun's network namespace.";
      };

      appdata = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Appdata directory to create, owned by the media user and group
          (mode 2775).
        '';
      };

      memory = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "2g";
        description = "Memory limit, with swap capped at the same value.";
      };
    };
  };

  forEach = f: lib.mkMerge (lib.mapAttrsToList f cfg);
in {
  options.homelab.containers = lib.mkOption {
    type = lib.types.attrsOf containerType;
    default = { };
    description = ''
      Common settings for the OCI container of the same name in
      `virtualisation.oci-containers.containers`.
    '';
  };

  config = {
    virtualisation.oci-containers.containers = forEach (name: c: {
      ${name} = {
        ports = lib.mapAttrsToList (port: _: "0.0.0.0:${port}:${port}") c.publish;
        extraOptions = lib.optional c.vpn "--network=container:gluetun"
          ++ lib.optionals (c.memory != null) [
            "--memory=${c.memory}"
            "--memory-swap=${c.memory}"
          ];
      };
    });

    systemd.services = forEach (name: c: {
      "podman-${name}" = lib.mkMerge [
        (lib.mkIf c.media {
          unitConfig.RequiresMountsFor = [ "/srv/media" ];
          after = [ "network-online.target" "srv-media.mount" ];
        })
        (lib.mkIf c.vpn {
          after = [ "podman-gluetun.service" "podman.service" ];
          requires = [ "podman-gluetun.service" "podman.service" ];
        })
      ];
    });

    homelab.firewall.restrict = forEach (_: c: c.publish);

    systemd.tmpfiles.rules = forEach (_: c:
      lib.mkIf (c.appdata != null) (lib.mkAfter [
        "d ${c.appdata} 2775 ${config.homelab.ids.user} media - -"
      ]));
  };
}
