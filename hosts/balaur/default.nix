{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/base.nix
    ../../modules/boot.nix
    ../../modules/access.nix
    ../../modules/networking.nix
    ../../modules/packages.nix
  ];

  networking = {
    hostName = "balaur";
    # Stable host identity required by ZFS pool import. Derived once from the
    # host name and now treated as persistent storage metadata.
    hostId = "8bdbe130";
  };

  # This destructive target layout is intentionally buildable for rehearsal,
  # but it is NON-DEPLOYABLE until the physical safety gates in issue 16 pass.
  warnings = [
    "Balaur rebuild configuration is non-deployable until physical issue 16"
  ];

  # DO NOT CHANGE after installation.
  system.stateVersion = "26.05";
}
