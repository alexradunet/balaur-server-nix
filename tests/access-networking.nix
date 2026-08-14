{ config, pkgs }:

let
  inherit (pkgs) lib;
  trustedInterfaces = [
    "enp100s0"
    "wlp98s0"
  ];
  alex = config.users.users.alex;
  andreea = config.users.users.andreea;
  expectedAlexKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJyNg0fSXVLH2obdAQ9lX2LP4NjATTydZxvu6RguwRWx alex@yoga-laptop"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJb2YvlmOvpu8On8kAdU0bgNQXLSekrVu/s/L7W+XPGV alex@balaur.space"
  ];
  alexSudoRules = builtins.filter (
    rule: builtins.elem "alex" rule.users
  ) config.security.sudo.extraRules;
  andreeaSudoRules = builtins.filter (
    rule: builtins.elem "andreea" rule.users || builtins.elem "andreea" rule.groups
  ) config.security.sudo.extraRules;
  ownerTmpfilesRules = [
    "d /home/alex 0700 alex users -"
    "d /srv/people/alex/apps 0700 alex users -"
    "d /home/andreea 0700 andreea users -"
    "d /srv/people/andreea/apps 0700 andreea users -"
  ];
  assertions = [
    {
      assertion =
        config.services.openssh.enable
        && !config.services.openssh.openFirewall
        && config.services.openssh.settings.AllowUsers == [ "alex" ]
        && !config.services.openssh.settings.KbdInteractiveAuthentication
        && config.services.openssh.settings.PermitRootLogin == "no"
        && !config.services.openssh.settings.PasswordAuthentication
        && !config.services.openssh.settings.X11Forwarding;
      message = "SSH must remain key-only, root-disabled, and restricted to Alex";
    }
    {
      assertion =
        alex.isNormalUser
        && alex.uid == null
        && alex.home == "/home/alex"
        && alex.homeMode == "0700"
        && builtins.elem "wheel" alex.extraGroups
        && alex.openssh.authorizedKeys.keys == expectedAlexKeys;
      message = "Alex must retain exactly both observed SSH keys and a dynamic owner ID";
    }
    {
      assertion =
        andreea.isNormalUser
        && andreea.uid == null
        && andreea.home == "/home/andreea"
        && andreea.homeMode == "0700"
        && andreea.hashedPassword == "!"
        && andreea.hashedPasswordFile == null
        && andreea.shell == "${pkgs.shadow}/bin/nologin"
        && andreea.extraGroups == [ ]
        && andreea.openssh.authorizedKeys.keys == [ ]
        && !(builtins.elem "wheel" andreea.extraGroups)
        && andreeaSudoRules == [ ];
      message = "Andreea must have a locked password, nologin shell, dynamic ID, and no SSH or sudo authority";
    }
    {
      assertion = lib.all (rule: builtins.elem rule config.systemd.tmpfiles.rules) ownerTmpfilesRules;
      message = "both ZFS owner home/apps mounts must receive private owner-specific modes";
    }
    {
      assertion =
        config.balaur.access.bootstrapPasswordlessSudo
        && config.security.sudo.wheelNeedsPassword
        && builtins.length alexSudoRules == 1
        &&
          (builtins.head alexSudoRules).commands == [
            {
              command = "ALL";
              options = [ "NOPASSWD" ];
            }
          ]
        && alex.hashedPasswordFile == null
        && lib.any (
          warning: lib.hasInfix "bootstrapPasswordlessSudo is still enabled" warning
        ) config.warnings;
      message = "bootstrap Alex sudo must remain visibly non-final until the human credential gate is complete";
    }
    {
      assertion =
        config.networking.firewall.allowedTCPPorts == [ ]
        && config.networking.firewall.allowedUDPPorts == [ ]
        && lib.all (
          interface:
          config.networking.firewall.interfaces.${interface}.allowedTCPPorts == [ 22 ]
          && config.networking.firewall.interfaces.${interface}.allowedUDPPorts == [ ]
        ) trustedInterfaces;
      message = "the baseline firewall must expose only SSH on trusted LAN interfaces";
    }
    {
      assertion =
        lib.all
          (
            port:
            !builtins.elem port config.networking.firewall.allowedTCPPorts
            && !builtins.elem port config.networking.firewall.allowedUDPPorts
            && lib.all (
              interface:
              !builtins.elem port config.networking.firewall.interfaces.${interface}.allowedTCPPorts
              && !builtins.elem port config.networking.firewall.interfaces.${interface}.allowedUDPPorts
            ) trustedInterfaces
          )
          [
            53
            80
            443
            6881
            8080
            8081
            8082
            8084
            8085
            8096
            8123
            9696
            11000
          ];
      message = "DNS, proxy, dashboard, and raw application ports must remain closed";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur access/networking invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-access-networking-tests" { } ''
    mkdir -p "$out"
    printf '%s\n' 'Access and networking baseline invariants passed.' > "$out/result"
  ''
