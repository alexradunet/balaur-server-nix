{ config, pkgs }:

let
  inherit (pkgs) lib;

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
        &&
          map (boot: boot.path) config.boot.loader.grub.mirroredBoots == [
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
        config.fileSystems."/srv/app-data".device == "/dev/disk/by-label/BALAUR_APP_DATA"
        && config.fileSystems."/srv/personal".device == "/dev/disk/by-label/BALAUR_PERSONAL"
        && config.fileSystems."/srv/media/ssd0".device == "/dev/disk/by-label/BALAUR_MEDIA_0"
        && config.fileSystems."/srv/media/ssd1".device == "/dev/disk/by-label/BALAUR_MEDIA_1"
        && lib.all (path: config.fileSystems.${path}.fsType == "ext4") [
          "/srv/app-data"
          "/srv/personal"
          "/srv/media/ssd0"
          "/srv/media/ssd1"
        ]
        && builtins.hasAttr "media" config.users.groups
        && builtins.elem "media" config.users.users.alex.extraGroups
        && builtins.any (
          rule:
          builtins.elem "alex" rule.users
          && builtins.any (
            entry: entry.command == "ALL" && builtins.elem "NOPASSWD" entry.options
          ) rule.commands
        ) config.security.sudo.extraRules;
      message = "application, personal, and replaceable-media storage layout must remain stable";
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
        &&
          config.systemd.services.balaur-backup.serviceConfig.LoadCredential
          == "passphrase:/var/lib/balaur-backup/passphrase"
        &&
          config.systemd.services.balaur-backup.unitConfig.ConditionPathExists
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
        && builtins.elem "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJyNg0fSXVLH2obdAQ9lX2LP4NjATTydZxvu6RguwRWx alex@yoga-laptop" config.users.users.alex.openssh.authorizedKeys.keys;
      message = "SSH must remain restricted to alex and require the authorized key";
    }
    {
      assertion =
        config.networking.firewall.allowedTCPPorts == [
          22
          6080
          6767
          6969
          7681
          7878
          8080
          8081
          8082
          8096
          8123
          8383
          8686
          8787
          8989
          9696
          22000
        ]
        &&
          config.networking.firewall.allowedUDPPorts == [
            21027
            22000
          ];
      message = "the firewall must expose exactly the intended LAN services";
    }
    {
      assertion =
        config.services.llama-cpp.host == "0.0.0.0"
        && config.services.syncthing.guiAddress == "0.0.0.0:8383"
        && !config.services.syncthing.openDefaultPorts
        && config.services.jellyfin.enable
        && !config.services.jellyfin.openFirewall
        && config.services.jellyfin.dataDir == "/srv/app-data/jellyfin"
        && config.services.jellyfin.configDir == "/srv/app-data/jellyfin/config"
        && config.services.jellyfin.logDir == "/srv/app-data/jellyfin/log"
        && builtins.elem "media" config.users.users.jellyfin.extraGroups
        && config.services.prowlarr.enable
        && !config.services.prowlarr.openFirewall
        && config.services.prowlarr.dataDir == "/srv/app-data/prowlarr"
        && config.services.prowlarr.settings.server.port == 9696
        && config.services.sonarr.enable
        && config.services.sonarr.dataDir == "/srv/app-data/sonarr"
        && config.services.radarr.enable
        && config.services.radarr.dataDir == "/srv/app-data/radarr"
        && config.services.lidarr.enable
        && config.services.lidarr.dataDir == "/srv/app-data/lidarr"
        && config.services.readarr.enable
        && config.services.readarr.dataDir == "/srv/app-data/readarr"
        && config.services.whisparr.enable
        && config.services.whisparr.dataDir == "/srv/app-data/whisparr"
        && config.services.whisparr.settings.server.port == 6969
        && config.services.bazarr.enable
        && config.services.bazarr.dataDir == "/srv/app-data/bazarr"
        && config.services.qbittorrent.enable
        && config.services.qbittorrent.profileDir == "/srv/app-data/qbittorrent"
        && config.services.qbittorrent.webuiPort == 8082
        && config.services.qbittorrent.torrentingPort == 6881
        && config.systemd.services.qbittorrent.serviceConfig.NetworkNamespacePath == "/run/netns/qbt-vpn"
        && builtins.elem "qbt-vpn.service" config.systemd.services.qbittorrent.requires
        && config.systemd.services.qbt-vpn.unitConfig.ConditionPathExists == "/srv/secrets/protonvpn.conf"
        && builtins.elem "qbittorrent.service" config.systemd.services.qbt-webui-proxy.requires
        && builtins.elem "qbt-host" config.networking.firewall.trustedInterfaces
        && !builtins.elem 6881 config.networking.firewall.allowedTCPPorts
        && !builtins.elem 6881 config.networking.firewall.allowedUDPPorts
        && lib.all (user: builtins.elem "media" config.users.users.${user}.extraGroups) [
          "sonarr"
          "radarr"
          "lidarr"
          "readarr"
          "whisparr"
          "bazarr"
          "qbittorrent"
        ]
        && config.services.home-assistant.enable
        && config.services.home-assistant.config.http.server_host == "0.0.0.0"
        && config.services.home-assistant.config.http.server_port == 8123
        && lib.all (component: builtins.elem component config.services.home-assistant.extraComponents) [
          "google_translate"
          "hue"
          "ibeacon"
          "ipp"
          "netatmo"
          "playstation_network"
          "radio_browser"
          "roborock"
          "samsungtv"
          "wiz"
        ]
        && !config.services.home-assistant.openFirewall
        && !config.services.home-assistant.openFirewallForComponents
        && config.hardware.bluetooth.enable
        && config.hardware.bluetooth.powerOnBoot
        && builtins.elem "CAP_NET_ADMIN" config.systemd.services.home-assistant.serviceConfig.CapabilityBoundingSet
        && builtins.elem "CAP_NET_RAW" config.systemd.services.home-assistant.serviceConfig.CapabilityBoundingSet
        && config.systemd.services.balaur-dashboard.environment.DASHBOARD_HOST == "0.0.0.0"
        && config.systemd.services.balaur-dashboard.environment.DASHBOARD_PORT == "8080"
        && config.systemd.services.herdr-web.environment.HERDR_WEB_LISTEN == "0.0.0.0";
      message = "application services must be reachable from the LAN";
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
    printf '%s\n' ${lib.escapeShellArg config.systemd.services.web-desktop-novnc.serviceConfig.ExecStart} \
      | grep --fixed-strings -- '--listen 0.0.0.0:6080'
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} configuration invariants passed.' > "$out/result"
  ''
