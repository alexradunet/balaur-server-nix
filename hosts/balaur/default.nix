{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/boot.nix
    ../../modules/access.nix
    ../../modules/networking.nix
    ../../modules/packages.nix
  ];

  networking.hostName = "balaur";

  # DO NOT CHANGE after installation.
  system.stateVersion = "26.05";
}
