{ pkgs, ... }:

{
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

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "fastflowlm"
      "obsidian"
    ];
  # Gives us nmcli + nmtui, including an easy Wi-Fi wizard.
  networking.networkmanager.enable = true;

  # ------------------------------------------------------------
  # Locale
  # ------------------------------------------------------------

  time.timeZone = "Europe/Bucharest";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";
}
