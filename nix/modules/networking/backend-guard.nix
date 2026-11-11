{ config, lib, ... }:

let
  cfg = config.homelab.firewall.restrict;

  parse = key:
    let parts = lib.splitString "/" key;
    in {
      port = lib.head parts;
      proto = if lib.length parts > 1 then lib.elemAt parts 1 else "tcp";
    };

  entries = lib.mapAttrsToList (key: rule:
    let p = parse key;
    in p // {
      inherit (rule) sources localContainers;
      chain = "guard_${p.proto}_${p.port}";
    }) cfg;

  jumpRule = e:
    "  fib daddr type local ${e.proto} dport ${e.port} jump ${e.chain}";

  guardChain = e:
    lib.concatStringsSep "\n" ([
      "chain ${e.chain} {"
      "  ct state established,related accept"
      "  iifname \"lo\" accept"
    ] ++ lib.optional e.localContainers "  iifname \"podman*\" accept"
      ++ lib.optional (e.sources != [ ])
      "  ip saddr { ${lib.concatStringsSep ", " e.sources} } accept"
      ++ [ "  drop" "}" ]);

  ruleType = lib.types.submodule {
    options = {
      sources = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "IPv4 addresses or CIDRs allowed to reach the port.";
      };
      localContainers = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description =
          "Whether containers on this host's own Podman bridges may reach the port.";
      };
    };
  };
in {
  options.homelab.firewall.restrict = lib.mkOption {
    type = lib.types.attrsOf
      (lib.types.coercedTo (lib.types.listOf lib.types.str)
        (sources: { inherit sources; }) ruleType);
    default = { };
    example = lib.literalExpression ''
      {
        "8088" = [ config.homelab.ips.gw ];
        "514/udp" = [ config.homelab.ips.router_vlan20 ];
        "8001" = {
          sources = [ config.homelab.ips.gw ];
          localContainers = false;
        };
      }
    '';
    description = ''
      Listening ports and the IPv4 sources allowed to reach them. Keys are
      "PORT" (TCP) or "PORT/udp"; values are a list of sources or an attribute
      set with `sources` and `localContainers`. Everything else, IPv6
      included, is dropped before Podman's DNAT, so this covers both published
      container ports and native services.
    '';
  };

  config = lib.mkIf (cfg != { }) {
    assertions = map (e: {
      assertion = lib.elem e.proto [ "tcp" "udp" ]
        && builtins.match "[0-9]+" e.port != null;
      message = ''
        homelab.firewall.restrict: invalid key for ${e.proto} port ${e.port}; use "PORT" or "PORT/udp".'';
    }) entries;

    networking.nftables.tables."backend-guard" = {
      family = "inet";
      content = ''
        chain prerouting {
          type filter hook prerouting priority -150; policy accept;
        ${lib.concatMapStringsSep "\n" jumpRule entries}
        }

        ${lib.concatMapStringsSep "\n\n" guardChain entries}
      '';
    };
  };
}
