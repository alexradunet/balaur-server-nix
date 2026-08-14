{
  description = "NixOS configuration for balaur";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko = {
      url = "github:nix-community/disko/ff8702b4de27f72b4c78573dfb89ec74e36abdf1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixarr = {
      url = "github:nix-media-server/nixarr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix/a8627b21b9107c5711c96b84f32a9a4b3d45295f";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pi.url = "github:lukasl-dev/pi.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      disko,
      nixarr,
      sops-nix,
      pi,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      piPackage = pi.packages.${system}.coding-agent;
      piSubagentsPackage = pkgs.callPackage ./packages/pi-subagents.nix { };
      piWebAccessPackage = pkgs.callPackage ./packages/pi-web-access.nix { };
    in
    {
      packages.${system} = {
        default = piPackage;
        pi = piPackage;
        pi-subagents = piSubagentsPackage;
        pi-web-access = piWebAccessPackage;
      };

      nixosConfigurations.balaur = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit piPackage piSubagentsPackage piWebAccessPackage;
        };
        modules = [
          disko.nixosModules.disko
          nixarr.nixosModules.default
          sops-nix.nixosModules.sops
          ./hosts/balaur/default.nix
        ];
      };

      checks.${system} = {
        configuration = import ./tests/configuration.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        storage = import ./tests/storage.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        disko-scripts = import ./tests/disko-scripts.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
          diskoRevision = disko.rev;
        };
        disko-install =
          (self.nixosConfigurations.balaur.extendModules {
            modules = [ ./tests/disko-install.nix ];
          }).config.system.build.installTest;
        access-networking = import ./tests/access-networking.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        network-access-vm = pkgs.testers.runNixOSTest (import ./tests/network-access-vm.nix);
        secrets = import ./tests/secrets.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        shared-services = import ./tests/shared-services.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        personal-containers = import ./tests/personal-containers.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        backup = import ./tests/backup.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        monitoring = import ./tests/monitoring.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        pi = piPackage;
        pi-subagents = piSubagentsPackage;
        pi-web-access = piWebAccessPackage;
      };
    };
}
