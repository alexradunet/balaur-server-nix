{
  description = "NixOS configuration for balaur";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    paseo = {
      url = "github:getpaseo/paseo";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    paseo-relay = {
      url = "github:getpaseo/paseo-relay";
      flake = false;
    };
  };

  outputs = { nixpkgs, paseo, paseo-relay, ... }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      paseoRelayPackage = pkgs.callPackage ./paseo-relay.nix { src = paseo-relay; };
    in
    {
      nixosConfigurations.balaur = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit paseoRelayPackage; };
        modules = [
          paseo.nixosModules.default
          ./configuration.nix
        ];
      };
    };
}
