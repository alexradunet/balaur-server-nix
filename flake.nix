{
  description = "NixOS configuration for balaur";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixarr = {
      url = "github:nix-media-server/nixarr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pi.url = "github:lukasl-dev/pi.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      nixarr,
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
          nixarr.nixosModules.default
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
        access-networking = import ./tests/access-networking.nix {
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
