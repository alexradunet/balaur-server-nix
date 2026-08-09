{
  description = "NixOS configuration for balaur";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    herdr.url = "github:herdrdev/herdr/v0.8.0";
  };

  outputs =
    {
      self,
      herdr,
      nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      herdrPackage = herdr.packages.${system}.default;
    in
    {
      nixosConfigurations.balaur = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit herdrPackage; };
        modules = [
          ./hardware-configuration.nix
          ./configuration.nix
        ];
      };

      checks.${system} = {
        configuration = import ./tests/configuration.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        dashboard = import ./tests/dashboard.nix { inherit pkgs; };
        herdr = herdrPackage;
      };
    };
}
