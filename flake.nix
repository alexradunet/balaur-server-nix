{
  description = "NixOS configuration for balaur";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    herdr.url = "github:herdrdev/herdr/v0.8.0";
  };

  outputs = { nixpkgs, herdr, ... }: {
    nixosConfigurations.balaur = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs.herdrPackage = herdr.packages.x86_64-linux.default;
      modules = [ ./configuration.nix ];
    };
  };
}
