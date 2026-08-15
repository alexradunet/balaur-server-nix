{ pkgs, ... }:

{
  # Keep the target platform on the compatibility pair proven for this host.
  boot.kernelPackages = pkgs.linuxPackages_6_18;
  boot.zfs.package = pkgs.zfs_2_4;

  # Required for the installed AMD platform and its Wi-Fi hardware.
  hardware.enableRedistributableFirmware = true;

  # ------------------------------------------------------------
  # Nix
  # ------------------------------------------------------------

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # Keep the store bounded while retaining a month of rollback generations.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.optimise.automatic = true;

  # Provide compressed emergency swap for model/service memory spikes without
  # adding another persistent disk dependency.
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # Gives us nmcli + nmtui, including an easy Wi-Fi wizard.
  networking.networkmanager.enable = true;

  # ------------------------------------------------------------
  # Locale
  # ------------------------------------------------------------

  time.timeZone = "Europe/Bucharest";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";
}
