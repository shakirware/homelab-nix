{ config, lib, ... }:

let
  fw = config.homelab.firewall;
  cfg = fw.restrict;

  published = lib.concatMap (c:
    lib.concatMap (spec:
      let
        protoParts = lib.splitString "/" spec;
        proto =
          if lib.length protoParts > 1 then lib.elemAt protoParts 1 else "tcp";
        parts = lib.splitString ":" (lib.head protoParts);
        n = lib.length parts;
        ip = if n == 3 then lib.head parts else "";
        hostPort = if n == 1 then "" else lib.elemAt parts (n - 2);
      in lib.optional (hostPort != "" && !lib.hasPrefix "127." ip)
      (if proto == "tcp" then hostPort else "${hostPort}/${proto}")) c.ports)
    (lib.attrValues config.virtualisation.oci-containers.containers);

  unguarded = lib.filter (key: !(cfg ? ${key})) (lib.unique published);

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
        default = fw.allowLocalContainers;
        description =
          "Whether containers on this host's own Podman bridges may reach the port.";
      };
    };
  };
in {
  options.homelab.firewall.allowLocalContainers = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Default for `localContainers`: whether containers on this host's own
      Podman bridges may reach restricted ports through the host address.
    '';
  };

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

  config = {
    assertions = [{
      assertion = unguarded == [ ];
      message =
        "homelab.firewall.restrict: published container ports without an entry: ${
          lib.concatStringsSep ", " unguarded
        }.";
    }] ++ map (e: {
      assertion = lib.elem e.proto [ "tcp" "udp" ]
        && builtins.match "[0-9]+" e.port != null;
      message = ''
        homelab.firewall.restrict: invalid key for ${e.proto} port ${e.port}; use "PORT" or "PORT/udp".'';
    }) entries;

    networking.nftables.tables."backend-guard" = lib.mkIf (cfg != { }) {
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
