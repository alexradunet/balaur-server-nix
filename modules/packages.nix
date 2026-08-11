{ fastFlowLMPackage, herdrPackage, piPackage, pkgs, ... }:

{
  # ------------------------------------------------------------
  # Useful server tools
  # ------------------------------------------------------------

  environment.systemPackages = with pkgs; [
    vim
    git
    nodejs
    gh
    curl
    wget
    htop
    tmux
    chromium
    obsidian
    herdrPackage
    fastFlowLMPackage
    piPackage
    pciutils
    usbutils
    gptfdisk
    mdadm
    borgbackup
  ];
}
