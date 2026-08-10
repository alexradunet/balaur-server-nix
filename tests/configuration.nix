{ config, pkgs }:

let
  inherit (pkgs) lib;

  gatewayHosts = builtins.attrNames config.services.nginx.virtualHosts;

  listensOnlyOnGateway =
    name:
    let
      listeners = config.services.nginx.virtualHosts.${name}.listen;
    in
    builtins.length listeners == 1
    && (builtins.head listeners).addr == "127.0.0.1"
    && (builtins.head listeners).port == 8080;

  hardened =
    service:
    let
      serviceConfig = config.systemd.services.${service}.serviceConfig;
    in
    serviceConfig.CapabilityBoundingSet == ""
    && serviceConfig.NoNewPrivileges
    && serviceConfig.PrivateDevices
    && serviceConfig.PrivateTmp
    && serviceConfig.ProtectSystem == "strict"
    && serviceConfig.RestrictNamespaces;

  assertions = [
    {
      assertion = config.networking.hostName == "balaur" && config.system.stateVersion == "26.05";
      message = "host identity and state version must remain stable";
    }
    {
      assertion =
        config.nixpkgs.hostPlatform.system == "x86_64-linux"
        && map (boot: boot.path) config.boot.loader.grub.mirroredBoots == [
          "/boot"
          "/boot-fallback"
        ]
        && config.fileSystems."/".device == "/dev/disk/by-uuid/3833ed98-7e78-4c5c-afa2-326cb47c0fd6"
        && config.fileSystems."/boot".device == "/dev/disk/by-uuid/9A81-7B8A"
        && config.fileSystems."/boot-fallback".device == "/dev/disk/by-uuid/9A81-CE59";
      message = "the installed host must retain its platform and boot filesystem layout";
    }
    {
      assertion =
        config.fileSystems."/mnt/balaur-backup".device == "/dev/disk/by-label/BALAUR_BACKUP"
        && lib.all (option: builtins.elem option config.fileSystems."/mnt/balaur-backup".options) [
          "noauto"
          "nodev"
          "nosuid"
          "noexec"
        ]
        && config.systemd.timers.balaur-backup.timerConfig.OnCalendar == "daily"
        && config.systemd.timers.balaur-backup.timerConfig.Persistent
        && config.systemd.services.balaur-backup.serviceConfig.LoadCredential
          == "passphrase:/var/lib/balaur-backup/passphrase"
        && config.systemd.services.balaur-backup.unitConfig.ConditionPathExists
          == "/dev/disk/by-label/BALAUR_BACKUP";
      message = "the encrypted USB backup must remain offline by default and use protected credentials";
    }
    {
      assertion =
        config.services.openssh.enable
        && config.services.openssh.settings.AllowUsers == [ "alex" ]
        && !config.services.openssh.settings.KbdInteractiveAuthentication
        && config.services.openssh.settings.PermitRootLogin == "no"
        && !config.services.openssh.settings.PasswordAuthentication
        && !config.services.openssh.settings.X11Forwarding
        && builtins.elem
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJyNg0fSXVLH2obdAQ9lX2LP4NjATTydZxvu6RguwRWx alex@yoga-laptop"
          config.users.users.alex.openssh.authorizedKeys.keys;
      message = "SSH must remain restricted to alex and require the authorized key";
    }
    {
      assertion =
        config.networking.firewall.allowedTCPPorts == [ 22 ]
        && config.networking.firewall.allowedUDPPorts == [ ];
      message = "SSH must be the only service exposed through the firewall";
    }
    {
      assertion =
        config.services.llama-cpp.host == "127.0.0.1"
        && config.services.syncthing.guiAddress == "127.0.0.1:8383"
        && !config.services.syncthing.openDefaultPorts
        && config.systemd.services.balaur-dashboard.environment.DASHBOARD_HOST == "127.0.0.1"
        && config.systemd.services.herdr-web.environment.HERDR_WEB_LISTEN == "127.0.0.1"
        && config.services.nginx.enable
        && gatewayHosts != [ ]
        && lib.all listensOnlyOnGateway gatewayHosts;
      message = "application services and the web gateway must bind only to loopback";
    }
    {
      assertion = lib.all hardened [
        "balaur-dashboard"
        "web-desktop-novnc"
      ];
      message = "network-facing custom services must retain their systemd sandboxing";
    }
  ];

  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur configuration invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-configuration-tests" { } ''
    grep --fixed-strings -- 'trap cleanup EXIT' ${config.systemd.services.balaur-backup.serviceConfig.ExecStart}
    grep --fixed-strings -- '-interface 127.0.0.1' ${config.systemd.services.web-desktop-vnc.serviceConfig.ExecStart}
    grep --fixed-strings -- '-rfbport 5910' ${config.systemd.services.web-desktop-vnc.serviceConfig.ExecStart}
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} configuration invariants passed.' > "$out/result"
  ''
