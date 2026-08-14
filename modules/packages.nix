{
  piPackage,
  piSubagentsPackage,
  piWebAccessPackage,
  pkgs,
  ...
}:

{
  environment.systemPackages = with pkgs; [
    vim
    git
    nodejs
    gh
    curl
    wget
    jq
    ripgrep
    htop
    tmux
    lsof
    ethtool
    pciutils
    usbutils
    gptfdisk
    mdadm
    borgbackup
    piPackage
  ];

  # Install pi's local extensions without coupling them to an application or
  # storage module. The target LLM provider is added only after issue 10.
  systemd.tmpfiles.rules = [
    "d /home/alex/.pi 0755 alex users -"
    "d /home/alex/.pi/agent 0755 alex users -"
    "d /home/alex/.pi/agent/extensions 0755 alex users -"
    "L+ /home/alex/.pi/agent/extensions/pi-subagents - - - - ${piSubagentsPackage}/lib/node_modules/@tintinweb/pi-subagents"
    "L+ /home/alex/.pi/agent/extensions/pi-web-access - - - - ${piWebAccessPackage}/lib/node_modules/pi-web-access"
  ];
}
