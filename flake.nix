{
  description = "NixOS configuration for balaur";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixarr = {
      url = "github:nix-media-server/nixarr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr.url = "github:herdrdev/herdr/v0.8.0";
    pi.url = "github:lukasl-dev/pi.nix";
  };

  outputs =
    {
      self,
      herdr,
      nixpkgs,
      nixarr,
      pi,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "fastflowlm";
      };
      fastFlowLMPackage = pkgs.callPackage ./fastflowlm.nix { };
      herdrPackage = herdr.packages.${system}.default;
      piPackage = pi.packages.${system}.coding-agent;
      piSubagentsPackage = pkgs.callPackage ./pi-subagents.nix { };
      piWebAccessPackage = pkgs.callPackage ./pi-web-access.nix { };
    in
    {
      packages.${system} = {
        default = fastFlowLMPackage;
        fastflowlm = fastFlowLMPackage;
      };

      nixosConfigurations.balaur = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit herdrPackage piPackage; };
        modules = [
          ./hardware-configuration.nix
          nixarr.nixosModules.default
          ./configuration.nix
        ];
      };

      checks.${system} = {
        configuration = import ./tests/configuration.nix {
          inherit pkgs;
          config = self.nixosConfigurations.balaur.config;
        };
        dashboard = import ./tests/dashboard.nix { inherit pkgs; };
        fastflowlm = fastFlowLMPackage;
        herdr = herdrPackage;
        pi = piPackage;
        pi-subagents = piSubagentsPackage;
        pi-web-access = piWebAccessPackage;
      };
    };
}
