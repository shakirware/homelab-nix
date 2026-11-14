{ config, lib, ... }:

let
  cfg = config.homelab.containers;

  publishType = lib.types.submodule {
    options = {
      sources = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Sources allowed to reach the port.";
      };
      to = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "Port inside the container, if different.";
      };
      localContainers = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description =
          "Passed to `homelab.firewall.restrict` when set.";
      };
    };
  };

  containerType = lib.types.submodule {
    options = {
      publish = lib.mkOption {
        type = lib.types.attrsOf (lib.types.coercedTo
          (lib.types.listOf lib.types.str) (sources: { inherit sources; })
          publishType);
        default = { };
        example = lib.literalExpression ''
          {
            "7878" = [ config.homelab.ips.gw ];
            "3003" = { sources = [ config.homelab.ips.gw ]; to = 3000; };
          }
        '';
        description = ''
          Host ports published on all host addresses, each restricted to its
          sources through `homelab.firewall.restrict`.
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
        type = lib.types.coercedTo lib.types.str lib.singleton
          (lib.types.listOf lib.types.str);
        default = [ ];
        description = ''
          Directories to create, owned by the media user and group
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
        ports = lib.mapAttrsToList (port: p:
          "0.0.0.0:${port}:${if p.to == null then port else toString p.to}")
          c.publish;
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

    homelab.firewall.restrict = forEach (_: c:
      lib.mapAttrs (_: p:
        { inherit (p) sources; } // lib.optionalAttrs (p.localContainers != null) {
          inherit (p) localContainers;
        }) c.publish);

    systemd.tmpfiles.rules = forEach (_: c:
      lib.mkAfter (map (dir: "d ${dir} 2775 ${config.homelab.ids.user} media - -")
        c.appdata));
  };
}
