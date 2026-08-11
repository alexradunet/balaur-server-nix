{ config, pkgs }:

let
  inherit (pkgs) lib;

  testedFlexgetConfig = pkgs.writeText "tested-flexget.yml" ''
    ${config.services.flexget.config}

    schedules: no
  '';

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
          80
          5050
          6080
          7681
          8081
          8082
          8096
          8123
          8383
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
        config.systemd.services.fastflowlm.environment.FLM_MODEL_PATH == "/srv/app-data/fastflowlm/models"
        && config.systemd.services.fastflowlm.environment.FLM_DISABLE_UPDATE_CHECK == "1"
        && lib.hasInfix "flm serve qwen3.6-moe:35b-a3b --host 0.0.0.0 --port 8081 --ctx-len 32768 --cors 0" config.systemd.services.fastflowlm.serviceConfig.ExecStart
        && config.systemd.services.fastflowlm.serviceConfig.LimitMEMLOCK == "infinity"
        && config.systemd.services.fastflowlm.serviceConfig.DeviceAllow == [ "/dev/accel/accel0 rw" ]
        && !config.systemd.services.fastflowlm.serviceConfig.PrivateDevices
        && builtins.elem "render" config.users.users.fastflowlm.extraGroups
        && builtins.elem "amdxdna" config.boot.kernelModules
        && lib.versionAtLeast config.boot.kernelPackages.kernel.version "7.0"
        && config.services.syncthing.guiAddress == "0.0.0.0:8383"
        && !config.services.syncthing.openDefaultPorts
        && !config.services.syncthing.overrideDevices
        && !config.services.syncthing.overrideFolders
        && config.services.syncthing.settings.folders.personal.path == "/srv/personal"
        && config.services.syncthing.settings.folders.personal.type == "sendreceive"
        && config.services.syncthing.settings.folders.personal.ignorePatterns == [ "/lost+found" ]
        && config.systemd.services.syncthing.unitConfig.RequiresMountsFor == [ "/srv/personal" ]
        && config.nixarr.enable
        && config.nixarr.mediaDir == "/srv/media/ssd0"
        && config.nixarr.stateDir == "/srv/app-data"
        && config.nixarr.vpn.enable
        && config.nixarr.vpn.wgConf == "/srv/secrets/protonvpn.conf"
        && config.users.groups.media.gid == null
        && lib.all (user: config.users.users.${user}.uid == null) [
          "jellyfin"
          "qbittorrent"
        ]
        && config.nixarr.jellyfin.enable
        && config.nixarr.qbittorrent.enable
        && lib.all (service: !config.nixarr.${service}.enable) [
          "prowlarr"
          "sonarr"
          "radarr"
          "lidarr"
        ]
        && !config.services.seerr.enable
        && config.nixarr.jellyfin.stateDir == "/srv/app-data/jellyfin"
        && config.services.jellyfin.dataDir == "/srv/app-data/jellyfin"
        && config.services.jellyfin.configDir == "/srv/app-data/jellyfin/config"
        && config.services.jellyfin.logDir == "/srv/app-data/jellyfin/log"
        && config.services.flexget.enable
        && config.services.flexget.user == "flexget"
        && config.services.flexget.homeDir == "/srv/app-data/flexget"
        && config.services.flexget.interval == "15m"
        && config.services.flexget.systemScheduler
        && config.users.users.flexget.group == "media"
        && lib.hasInfix "variables: variables.yml" config.services.flexget.config
        && lib.hasInfix "bind: 0.0.0.0" config.services.flexget.config
        && lib.hasInfix "port: 5050" config.services.flexget.config
        && lib.hasInfix "web_ui: yes" config.services.flexget.config
        && lib.hasInfix "filelist_api" config.services.flexget.config
        && lib.hasInfix "interval: 15 minutes" config.services.flexget.config
        && lib.hasInfix "list_match:" config.services.flexget.config
        && lib.hasInfix "imdb_lookup: yes" config.services.flexget.config
        && lib.hasInfix "quality: 2160p" config.services.flexget.config
        && lib.hasInfix "path: /srv/media/ssd0/library/movies" config.services.flexget.config
        && lib.hasInfix "path: /srv/media/ssd1/library/tv" config.services.flexget.config
        && builtins.any (
          command: lib.hasInfix "flexget-prepare-secrets" command
        ) config.systemd.services.flexget.serviceConfig.ExecStartPre
        && builtins.any (
          command: lib.hasInfix "flexget-set-web-password" command
        ) config.systemd.services.flexget.serviceConfig.ExecStartPre
        && builtins.elem "qbt-webui-proxy.service" config.systemd.services.flexget.requires
        && builtins.elem "qbt-webui-proxy.service" config.systemd.services.flexget-runner.requires
        && builtins.elem "/srv/app-data" config.systemd.services.flexget.unitConfig.RequiresMountsFor
        && builtins.elem "/srv/media/ssd0" config.systemd.services.flexget-runner.unitConfig.RequiresMountsFor
        && builtins.elem "/srv/media/ssd1" config.systemd.services.flexget-runner.unitConfig.RequiresMountsFor
        && config.services.qbittorrent.profileDir == "/srv/app-data/qbittorrent"
        && config.services.qbittorrent.webuiPort == 8082
        && config.services.qbittorrent.torrentingPort == 6881
        &&
          config.services.qbittorrent.serverConfig.BitTorrent."Session\\DefaultSavePath"
          == "/srv/media/ssd0/downloads/complete"
        &&
          config.services.qbittorrent.serverConfig.BitTorrent."Session\\TempPath"
          == "/srv/media/ssd0/downloads/incomplete"
        && !config.services.qbittorrent.serverConfig.Preferences."WebUI\\AuthSubnetWhitelistEnabled"
        && config.services.qbittorrent.serverConfig.Preferences."WebUI\\CSRFProtection"
        && config.services.qbittorrent.serverConfig.Preferences."WebUI\\LocalHostAuth"
        && config.systemd.services.qbittorrent.serviceConfig.Restart == "on-failure"
        && config.systemd.services.qbittorrent.serviceConfig.RestartSec == 10
        && config.systemd.services.qbittorrent.serviceConfig.UMask == "0002"
        && builtins.any (
          command: lib.hasInfix "qbittorrent-webui-password" command
        ) config.systemd.services.qbittorrent.serviceConfig.ExecStartPre
        && config.systemd.services.qbittorrent.vpnConfinement.enable
        && config.systemd.services.qbittorrent.vpnConfinement.vpnNamespace == "wg"
        && config.vpnNamespaces.wg.wireguardConfigFile == "/srv/secrets/protonvpn.conf"
        && lib.hasInfix "wg-route-proton-dns" (toString config.systemd.services.wg.serviceConfig.ExecStartPost)
        && builtins.any (
          entry: entry.port == 6881 && entry.protocol == "both"
        ) config.vpnNamespaces.wg.openVPNPorts
        && builtins.any (
          entry: entry.from == 8082 && entry.to == 8082
        ) config.vpnNamespaces.wg.portMappings
        && builtins.elem "qbittorrent.service" config.systemd.services.qbt-webui-proxy.requires
        && lib.hasInfix "TCP:192.168.15.1:8082" config.systemd.services.qbt-webui-proxy.serviceConfig.ExecStart
        && !builtins.elem 6881 config.networking.firewall.allowedTCPPorts
        && !builtins.elem 6881 config.networking.firewall.allowedUDPPorts
        && lib.all (
          entry: builtins.elem entry.mount config.systemd.services.${entry.service}.unitConfig.RequiresMountsFor
        ) [
          { service = "jellyfin"; mount = "/srv/media/ssd0"; }
          { service = "jellyfin"; mount = "/srv/media/ssd1"; }
          { service = "qbittorrent"; mount = "/srv/media/ssd0"; }
          { service = "qbittorrent"; mount = "/srv/media/ssd1"; }
          { service = "flexget"; mount = "/srv/app-data"; }
          { service = "flexget-runner"; mount = "/srv/media/ssd0"; }
          { service = "flexget-runner"; mount = "/srv/media/ssd1"; }
        ]
        && lib.all (user: config.users.users.${user}.group == "media") [
          "jellyfin"
          "qbittorrent"
          "flexget"
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
        && config.systemd.services.balaur-dashboard.environment.DASHBOARD_HOST == "127.0.0.1"
        && config.systemd.services.balaur-dashboard.environment.DASHBOARD_PORT == "8080"
        && config.services.caddy.enable
        && lib.hasInfix "reverse_proxy 127.0.0.1:8080" config.services.caddy.virtualHosts."http://balaur.home.arpa".extraConfig
        && config.systemd.services.herdr-web.environment.HERDR_WEB_LISTEN == "0.0.0.0";
      message = "application services must be reachable from the LAN";
    }
    {
      assertion = lib.all hardened [
        "flexget"
        "flexget-runner"
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
  pkgs.runCommand "balaur-configuration-tests"
    { nativeBuildInputs = [ config.services.flexget.package ]; }
    ''
    grep --fixed-strings -- 'trap cleanup EXIT' ${config.systemd.services.balaur-backup.serviceConfig.ExecStart}
    test -f ${config.services.flexget.package}/${pkgs.python3.sitePackages}/flexget/ui/v2/dist/index.html
    printf '%s\n' ${lib.escapeShellArg config.services.flexget.config} \
      | grep --fixed-strings -- "password: '{? qbittorrent.password ?}'"

    mkdir flexget-check
    cp ${testedFlexgetConfig} flexget-check/flexget.yml
    printf '%s\n' \
      '{"qbittorrent":{"password":"test"},"filelist":{"username":"test","passkey":"test"}}' \
      > flexget-check/variables.yml
    flexget -c "$PWD/flexget-check/flexget.yml" check
    flexget -c "$PWD/flexget-check/flexget.yml" execute \
      --tasks movies --learn --dump-config > flexget-effective
    grep --fixed-strings -- 'interval: 15 minutes' flexget-effective
    grep --fixed-strings -- 'remove_on_match: true' flexget-effective
    grep --fixed-strings -- '-interface 127.0.0.1' ${config.systemd.services.web-desktop-vnc.serviceConfig.ExecStart}
    grep --fixed-strings -- '-rfbport 5910' ${config.systemd.services.web-desktop-vnc.serviceConfig.ExecStart}
    printf '%s\n' ${lib.escapeShellArg config.systemd.services.web-desktop-novnc.serviceConfig.ExecStart} \
      | grep --fixed-strings -- '--listen 0.0.0.0:6080'
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} configuration invariants passed.' > "$out/result"
  ''
