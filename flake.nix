{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

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

  outputs = { self, nixpkgs, sops-nix, nixos-generators, colmena, ... }:
    let
      system = "x86_64-linux";

      lab = { cidr = "192.168.1.0/24"; };
      home = { cidr = "192.168.1.0/24"; };

      sshKeyEnv = builtins.getEnv "COLMENA_SSH_KEY";
      targetUserEnv = builtins.getEnv "COLMENA_TARGET_USER";
      targetUser = if targetUserEnv == "" then "shakir" else targetUserEnv;

      sshOptions = [ "-o" "IdentitiesOnly=yes" ]
        ++ (if sshKeyEnv == "" then [ ] else [ "-i" sshKeyEnv ]);

      # Shared for all hosts
      commonModules = [
        sops-nix.nixosModules.sops
        ./modules/common/addresses.nix
        ./modules/common/base.nix
        ./modules/common/networking.nix
        ./modules/common/proxmox-hardware.nix
      ];

      mkHost = hostName: extraModules:
        nixpkgs.lib.nixosSystem {
          inherit system;

          specialArgs = { inherit lab home; };

          modules = [
            { networking.hostName = hostName; }
            ./hosts/${hostName}/configuration.nix
          ] ++ commonModules ++ extraModules;
        };
    in {
      nixosConfigurations = {
        vm-gw = mkHost "vm-gw" [ ./modules/gw/gw.nix ];
        vm-storage = mkHost "vm-storage" [ ./modules/storage/storage.nix ];
        vm-media = mkHost "vm-media" [ ./modules/media/media.nix ];
        vm-sensitive =
          mkHost "vm-sensitive" [ ./modules/sensitive/sensitive.nix ];
      };

      packages.${system} = {
        # Build the Proxmox template image
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

      colmenaHive = colmena.lib.makeHive {
        meta = { nixpkgs = import nixpkgs { system = system; }; };

        defaults = { ... }: {
          imports = [ ({ ... }: { _module.args = { inherit lab home; }; }) ]
            ++ commonModules;

          deployment.targetUser = targetUser;
          deployment.sshOptions = sshOptions;
        };

        vm-gw = {
          deployment.targetHost = "vm-gw";
          imports = [ ./hosts/vm-gw/configuration.nix ./modules/gw/gw.nix ];
        };

        vm-media = {
          deployment.targetHost = "vm-media";
          imports =
            [ ./hosts/vm-media/configuration.nix ./modules/media/media.nix ];
        };

        vm-storage = {
          deployment.targetHost = "vm-storage";
          imports = [
            ./hosts/vm-storage/configuration.nix
            ./modules/storage/storage.nix
          ];
        };

        vm-sensitive = {
          deployment.targetHost = "vm-sensitive";
          imports = [
            ./hosts/vm-sensitive/configuration.nix
            ./modules/sensitive/sensitive.nix
          ];
        };
      };

    };
}
