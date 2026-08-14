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
    "d /home/alex/files 0700 alex users -"
    "d /home/andreea/files 0700 andreea users -"
    "d /srv/media 2750 alex media -"
  ];
  expectedHouseholdNames = [
    "balaur.home.arpa"
    "notes.alex.home.arpa"
    "paperless.alex.home.arpa"
    "budget.alex.home.arpa"
    "chat.alex.home.arpa"
    "notes.andreea.home.arpa"
    "paperless.andreea.home.arpa"
    "budget.andreea.home.arpa"
    "chat.andreea.home.arpa"
    "home-assistant.home.arpa"
    "jellyfin.home.arpa"
    "downloads.home.arpa"
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
        && builtins.elem "media" alex.extraGroups
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
        && andreea.extraGroups == [ "media" ]
        && andreea.openssh.authorizedKeys.keys == [ ]
        && !(builtins.elem "wheel" andreea.extraGroups)
        && !(builtins.elem "networkmanager" andreea.extraGroups)
        && andreeaSudoRules == [ ];
      message = "Andreea must have a locked password, nologin shell, dynamic ID, and no SSH or sudo authority";
    }
    {
      assertion = lib.all (rule: builtins.elem rule config.systemd.tmpfiles.rules) ownerTmpfilesRules;
      message = "owner storage, exact SMB exports, and media ownership must receive explicit modes";
    }
    {
      assertion =
        config.balaur.network.trustedInterfaces == trustedInterfaces
        && config.balaur.network.serverAddress == "192.168.50.2"
        && config.balaur.network.routerAddress == "192.168.50.1"
        && config.balaur.network.householdNames == expectedHouseholdNames
        && config.balaur.ingress.reverseProxies == { };
      message = "private DNS and the empty typed reverse-proxy registration seam must remain exact";
    }
    {
      assertion =
        config.services.coredns.enable
        && lib.hasInfix "home.arpa:53" config.services.coredns.config
        && lib.hasInfix "bind 192.168.50.2" config.services.coredns.config
        && lib.hasInfix "forward . 192.168.50.1" config.services.coredns.config
        && !(lib.hasInfix "log" config.services.coredns.config);
      message = "CoreDNS must authoritatively serve home.arpa, forward elsewhere only to ASUS, and omit query logging";
    }
    {
      assertion =
        config.services.caddy.enable
        && !config.services.caddy.enableReload
        && !config.services.caddy.openFirewall
        && config.services.caddy.acmeCA == null
        && config.services.caddy.email == null
        &&
          builtins.attrNames config.services.caddy.virtualHosts == [
            "http://balaur.home.arpa"
            "https://balaur.home.arpa"
          ]
        && lib.all (host: host.listenAddresses == [ "192.168.50.2" ] && host.logFormat == null) (
          builtins.attrValues config.services.caddy.virtualHosts
        )
        &&
          lib.hasInfix "tls internal"
            config.services.caddy.virtualHosts."https://balaur.home.arpa".extraConfig
        &&
          lib.hasInfix "respond @health"
            config.services.caddy.virtualHosts."https://balaur.home.arpa".extraConfig;
      message = "Caddy must expose only the bound internal-CA host health endpoint before services register";
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
          config.networking.firewall.interfaces.${interface}.allowedTCPPorts == [
            22
            53
            80
            443
          ]
          && config.networking.firewall.interfaces.${interface}.allowedUDPPorts == [ 53 ]
        ) trustedInterfaces;
      message = "only SSH, DNS, and Caddy ingress may be exposed on trusted LAN interfaces";
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
            137
            138
            139
            445
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
      message = "credential-gated SMB, NetBIOS, dashboard, and raw application ports must remain closed";
    }
    {
      assertion =
        !config.balaur.samba.credentials.ready
        && config.balaur.samba.credentials.passwordFiles.alex == null
        && config.balaur.samba.credentials.passwordFiles.andreea == null
        && !config.services.samba.enable
        && !config.services.samba.openFirewall
        && !config.services.samba.nmbd.enable
        && !config.services.samba.winbindd.enable
        &&
          builtins.attrNames config.services.samba.settings == [
            "alex"
            "andreea"
            "global"
            "media"
          ]
        && config.services.samba.settings.alex.path == "/home/alex/files"
        && config.services.samba.settings.andreea.path == "/home/andreea/files"
        && config.services.samba.settings.media.path == "/srv/media"
        && config.services.samba.settings.media."write list" == [ "alex" ]
        && config.services.samba.settings.global."server min protocol" == "SMB2"
        && config.services.samba.settings.global."server max protocol" == "SMB3"
        && config.services.samba.settings.global."smb ports" == "445"
        && config.services.samba.settings.global."map to guest" == "Never"
        && lib.any (warning: lib.hasInfix "Samba is fail-closed" warning) config.warnings;
      message = "Samba policy must remain hardened and credential-gated with exactly three exports";
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
