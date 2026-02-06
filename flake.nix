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

      mkHost = hostName: modulePath:
        nixpkgs.lib.nixosSystem {
          inherit system;

          specialArgs = { inherit lab home; };

          modules = [
            sops-nix.nixosModules.sops
            { networking.hostName = hostName; }
            modulePath
          ];
        };
    in {
      nixosConfigurations = {
        vm-gw = mkHost "vm-gw" ./nix/hosts/vm-gw/default.nix;
        vm-media = mkHost "vm-media" ./nix/hosts/vm-media/default.nix;
        vm-storage = mkHost "vm-storage" ./nix/hosts/vm-storage/default.nix;
        vm-sensitive =
          mkHost "vm-sensitive" ./nix/hosts/vm-sensitive/default.nix;
        vm-apps = mkHost "vm-apps" ./nix/hosts/vm-apps/default.nix;
        vm-monitoring =
          mkHost "vm-monitoring" ./nix/hosts/vm-monitoring/default.nix;
      };

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

      colmenaHive = colmena.lib.makeHive {
        meta = { nixpkgs = import nixpkgs { system = system; }; };

        defaults = { ... }: {
          imports = [
            sops-nix.nixosModules.sops
            ({ ... }: { _module.args = { inherit lab home; }; })
          ];

          deployment.targetUser = targetUser;
          deployment.sshOptions = sshOptions;
        };

        vm-gw = {
          deployment.targetHost = "vm-gw";
          imports = [
            { networking.hostName = "vm-gw"; }
            ./nix/hosts/vm-gw/default.nix
          ];
        };

        vm-media = {
          deployment.targetHost = "vm-media";
          imports = [
            { networking.hostName = "vm-media"; }
            ./nix/hosts/vm-media/default.nix
          ];
        };

        vm-storage = {
          deployment.targetHost = "vm-storage";
          imports = [
            { networking.hostName = "vm-storage"; }
            ./nix/hosts/vm-storage/default.nix
          ];
        };

        vm-sensitive = {
          deployment.targetHost = "vm-sensitive";
          imports = [
            { networking.hostName = "vm-sensitive"; }
            ./nix/hosts/vm-sensitive/default.nix
          ];
        };

        vm-apps = {
          deployment.targetHost = "vm-apps";
          imports = [
            { networking.hostName = "vm-apps"; }
            ./nix/hosts/vm-apps/default.nix
          ];
        };

        vm-monitoring = {
          deployment.targetHost = "vm-monitoring";
          imports = [
            { networking.hostName = "vm-monitoring"; }
            ./nix/hosts/vm-monitoring/default.nix
          ];
        };
      };
    };
}
