{
  description = "NixOS configuration for balaur";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    herdr.url = "github:herdrdev/herdr/v0.8.0";
    pi.url = "github:lukasl-dev/pi.nix";
  };

  outputs =
    {
      self,
      herdr,
      nixpkgs,
      pi,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      herdrPackage = herdr.packages.${system}.default;
      piPackage = pi.packages.${system}.coding-agent;
      piSubagentsPackage = pkgs.callPackage ./pi-subagents.nix { };
      piWebAccessPackage = pkgs.callPackage ./pi-web-access.nix { };
    in
    {
      nixosConfigurations.balaur = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit herdrPackage piPackage; };
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
        pi = piPackage;
        pi-subagents = piSubagentsPackage;
        pi-web-access = piWebAccessPackage;
      };
    };
}
