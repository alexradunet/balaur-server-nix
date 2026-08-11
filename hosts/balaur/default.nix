{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/boot.nix
    ../../modules/desktop.nix
    ../../modules/access.nix
    ../../modules/syncthing.nix
    ../../modules/media.nix
    ../../modules/flexget.nix
    ../../modules/home-assistant.nix
    ../../modules/storage.nix
    ../../modules/backup.nix
    ../../modules/fastflowlm.nix
    ../../modules/web-services.nix
    ../../modules/networking.nix
    ../../modules/packages.nix
  ];

  networking.hostName = "balaur";

  # DO NOT CHANGE after installation.
  system.stateVersion = "26.05";
}
