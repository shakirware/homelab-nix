{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  description = "Homelab NixOS VMs on Proxmox";

  outputs = { self, nixpkgs, nixpkgs-unstable, sops-nix, nixos-generators, colmena, ... }:
    let
      system = "x86_64-linux";

      unstablePkgs = import nixpkgs-unstable {
        inherit system;
      };

      lab = { cidr = "192.168.20.0/24"; };
      home = { cidr = "192.168.1.0/24"; };
      iot = { cidr = "192.168.40.0/24"; };

      sshKeyEnv = builtins.getEnv "COLMENA_SSH_KEY";
      targetUserEnv = builtins.getEnv "COLMENA_TARGET_USER";
      targetUser = if targetUserEnv == "" then "shakir" else targetUserEnv;

      sshOptions = [ "-o" "IdentitiesOnly=yes" ]
        ++ (if sshKeyEnv == "" then [ ] else [ "-i" sshKeyEnv ]);

      hosts = builtins.attrNames (nixpkgs.lib.filterAttrs (_: type: type == "directory")
        (builtins.readDir ./nix/hosts));

      hostModule = hostName: ./nix/hosts + "/${hostName}/default.nix";

      mkHost = hostName: modulePath:
        nixpkgs.lib.nixosSystem {
          inherit system;

          specialArgs = { inherit lab home iot unstablePkgs; };

          modules = [
            sops-nix.nixosModules.sops
            { networking.hostName = hostName; }
            modulePath
          ];
        };
    in {
      nixosConfigurations = nixpkgs.lib.genAttrs hosts
        (hostName: mkHost hostName (hostModule hostName));

      packages.${system} = {
        proxmox-template = nixos-generators.nixosGenerate {
          system = system;
          format = "proxmox";
          modules = [
            ./templates/proxmox-template.nix
            { nix.registry.nixpkgs.flake = nixpkgs; }
          ];
        };

        colmena = colmena.packages.${system}.colmena;
      };

      colmenaHive = colmena.lib.makeHive ({
        meta = { nixpkgs = import nixpkgs { system = system; }; };

        defaults = { ... }: {
          imports = [
            sops-nix.nixosModules.sops
            ({ ... }: { _module.args = { inherit lab home iot unstablePkgs; }; })
          ];

          deployment.targetUser = targetUser;
          deployment.sshOptions = sshOptions;
        };
      } // nixpkgs.lib.genAttrs hosts (hostName: {
        deployment.targetHost = hostName;
        imports = [
          { networking.hostName = hostName; }
          (hostModule hostName)
        ];
      }));
    };
}
