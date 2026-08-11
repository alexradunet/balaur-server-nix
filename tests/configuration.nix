{ config, pkgs }:

let
  inherit (pkgs) lib;

  hardened =
    service:
    let
      serviceConfig = config.systemd.services.${service}.serviceConfig;
    in
    serviceConfig.CapabilityBoundingSet
      == (
        if service == "arr-qbittorrent-sync" then
          [ "CAP_DAC_READ_SEARCH" ]
        else
          ""
      )
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
      assertion = builtins.elem pkgs.nodejs config.environment.systemPackages;
      message = "Node.js must be installed in the system profile";
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
        && !config.services.openssh.openFirewall
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
        config.networking.firewall.allowedTCPPorts == [ ]
        && config.networking.firewall.allowedUDPPorts == [ ]
        && config.networking.firewall.interfaces.enp100s0.allowedTCPPorts == [
          22
          80
          5230
          7878
          8081
          8082
          8083
          8096
          8123
          8383
          8989
          9696
          22000
        ]
        && config.networking.firewall.interfaces.enp100s0.allowedUDPPorts == [
          21027
          22000
        ]
        && config.networking.firewall.interfaces.wlp98s0.allowedTCPPorts
          == config.networking.firewall.interfaces.enp100s0.allowedTCPPorts
        && config.networking.firewall.interfaces.wlp98s0.allowedUDPPorts
          == config.networking.firewall.interfaces.enp100s0.allowedUDPPorts;
      message = "the firewall must expose exactly the intended LAN services";
    }
    {
      assertion =
        config.systemd.services.fastflowlm.environment.FLM_MODEL_PATH == "/srv/app-data/fastflowlm/models"
        && config.systemd.services.fastflowlm.environment.FLM_DISABLE_UPDATE_CHECK == "1"
        && config.nix.gc.automatic
        && config.nix.gc.options == "--delete-older-than 30d"
        && config.nix.optimise.automatic
        && config.zramSwap.enable
        && config.zramSwap.memoryPercent == 25
        && config.services.smartd.enable
        && config.services.smartd.autodetect
        && !config.services.smartd.notifications.mail.enable
        && !config.services.smartd.notifications.x11.enable
        && lib.hasInfix "flm serve qwen3.6-moe:35b-a3b --host 0.0.0.0 --port 8081 --ctx-len 32768 --cors 0" config.systemd.services.fastflowlm.serviceConfig.ExecStart
        && config.systemd.services.fastflowlm.serviceConfig.LimitMEMLOCK == "infinity"
        && config.systemd.services.fastflowlm.serviceConfig.DeviceAllow == [ "/dev/accel/accel0 rw" ]
        && config.systemd.services.fastflowlm.unitConfig.RequiresMountsFor == [ "/srv/app-data" ]
        && !config.systemd.services.fastflowlm.serviceConfig.PrivateDevices
        && builtins.elem "render" config.users.users.fastflowlm.extraGroups
        && builtins.elem "amdxdna" config.boot.kernelModules
        && lib.versionAtLeast config.boot.kernelPackages.kernel.version "7.0"
        && config.services.syncthing.guiAddress == "0.0.0.0:8383"
        && !config.services.syncthing.openDefaultPorts
        && config.services.syncthing.settings.options.globalAnnounceEnabled == false
        && config.services.syncthing.settings.options.localAnnounceEnabled
        && config.services.syncthing.settings.options.natEnabled == false
        && config.services.syncthing.settings.options.relaysEnabled == false
        && config.services.syncthing.settings.options.listenAddresses == [
          "tcp://192.168.50.13:22000"
          "quic://192.168.50.13:22000"
        ]
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
        && config.users.groups.prowlarr.gid == 983
        && lib.all (user: config.users.users.${user}.uid == null) [
          "jellyfin"
          "qbittorrent"
        ]
        && config.users.users.prowlarr.uid == 986
        && config.users.users.sonarr.uid == 274
        && config.users.users.radarr.uid == 275
        && lib.all (service: config.nixarr.${service}.enable) [
          "jellyfin"
          "prowlarr"
          "sonarr"
          "radarr"
          "qbittorrent"
        ]
        && config.nixarr.prowlarr.settings-sync.enable-nixarr-apps
        && !config.nixarr.lidarr.enable
        && !config.services.seerr.enable
        && config.nixarr.jellyfin.stateDir == "/srv/app-data/jellyfin"
        && config.services.jellyfin.dataDir == "/srv/app-data/jellyfin"
        && config.services.jellyfin.configDir == "/srv/app-data/jellyfin/config"
        && config.services.jellyfin.logDir == "/srv/app-data/jellyfin/log"
        && config.nixarr.prowlarr.stateDir == "/srv/app-data/prowlarr"
        && !config.systemd.services.prowlarr.serviceConfig.DynamicUser
        && config.nixarr.sonarr.stateDir == "/srv/app-data/sonarr"
        && config.nixarr.radarr.stateDir == "/srv/app-data/radarr"
        && config.services.prowlarr.settings.auth.required == "DisabledForLocalAddresses"
        && config.services.sonarr.settings.auth.required == "DisabledForLocalAddresses"
        && config.services.radarr.settings.auth.required == "DisabledForLocalAddresses"
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
        && builtins.elem "CAP_DAC_READ_SEARCH"
          config.systemd.services.arr-qbittorrent-sync.serviceConfig.CapabilityBoundingSet
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
        && builtins.elem "qbt-webui-proxy.service" config.systemd.services.arr-qbittorrent-sync.after
        && builtins.elem "sonarr.service" config.systemd.services.arr-qbittorrent-sync.after
        && builtins.elem "radarr.service" config.systemd.services.arr-qbittorrent-sync.after
        && config.systemd.services.arr-qbittorrent-sync.serviceConfig.TimeoutStartSec == 240
        && lib.all (
          entry: builtins.elem entry.mount config.systemd.services.${entry.service}.unitConfig.RequiresMountsFor
        ) [
          { service = "jellyfin"; mount = "/srv/media/ssd0"; }
          { service = "jellyfin"; mount = "/srv/media/ssd1"; }
          { service = "prowlarr"; mount = "/srv/app-data"; }
          { service = "sonarr"; mount = "/srv/media/ssd1"; }
          { service = "radarr"; mount = "/srv/media/ssd0"; }
          { service = "qbittorrent"; mount = "/srv/media/ssd0"; }
          { service = "qbittorrent"; mount = "/srv/media/ssd1"; }
        ]
        && lib.all (user: config.users.users.${user}.group == "media") [
          "jellyfin"
          "sonarr"
          "radarr"
          "qbittorrent"
        ]
        && config.services.memos.enable
        && config.services.memos.dataDir == "/srv/app-data/memos"
        && !config.services.memos.openFirewall
        && config.services.memos.settings.MEMOS_MODE == "prod"
        && config.services.memos.settings.MEMOS_ADDR == "0.0.0.0"
        && config.services.memos.settings.MEMOS_PORT == "5230"
        && config.services.memos.settings.MEMOS_DATA == "/srv/app-data/memos"
        && config.services.memos.settings.MEMOS_DRIVER == "sqlite"
        && config.services.memos.settings.MEMOS_INSTANCE_URL == "http://balaur.home.arpa:5230"
        && config.systemd.services.memos.unitConfig.RequiresMountsFor == [ "/srv/app-data" ]
        && config.services.open-webui.enable
        && config.services.open-webui.host == "127.0.0.1"
        && config.services.open-webui.port == 3000
        && config.services.open-webui.stateDir == "/var/lib/open-webui"
        && !config.services.open-webui.openFirewall
        && config.services.open-webui.environment.ENABLE_OLLAMA_API == "False"
        && config.services.open-webui.environment.ENABLE_OPENAI_API == "True"
        && config.services.open-webui.environment.OPENAI_API_BASE_URLS == "http://127.0.0.1:8081/v1"
        && config.services.open-webui.environment.OPENAI_API_KEYS == "fastflowlm"
        && config.services.open-webui.environment.DEFAULT_MODELS == "qwen3.6-moe:35b-a3b"
        && config.services.open-webui.environment.ENABLE_SIGNUP == "False"
        && config.services.open-webui.environment.ANONYMIZED_TELEMETRY == "False"
        && builtins.elem "fastflowlm.service" config.systemd.services.open-webui.wants
        && builtins.elem "fastflowlm.service" config.systemd.services.open-webui.after
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
        && lib.hasInfix "reverse_proxy 127.0.0.1:3000" config.services.caddy.virtualHosts."http://balaur.home.arpa:8083".extraConfig
        && !(builtins.hasAttr "herdr-web" config.systemd.services)
        && !(builtins.hasAttr "web-desktop-novnc" config.systemd.services);
      message = "application access controls and dashboard routing must remain stable";
    }
    {
      assertion = lib.all hardened [
        "arr-qbittorrent-sync"
        "balaur-dashboard"
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
    grep --fixed-strings -- '--exclude /srv/app-data/fastflowlm/models' ${config.systemd.services.balaur-backup.serviceConfig.ExecStart}
    grep --fixed-strings -- '/var/lib/hass' ${config.systemd.services.balaur-backup.serviceConfig.ExecStart}
    grep --fixed-strings -- '/var/lib/open-webui' ${config.systemd.services.balaur-backup.serviceConfig.ExecStart}
    grep --fixed-strings -- 'systemctl restart qbittorrent.service' ${config.systemd.services.arr-qbittorrent-sync.serviceConfig.ExecStart}
    grep --fixed-strings -- '--sync-categories' ${config.systemd.services.arr-qbittorrent-sync.serviceConfig.ExecStart}
    grep --fixed-strings -- '"Accept-Encoding": "gzip"' ${../arr-qbittorrent-sync.py}
    grep --fixed-strings -- '-interface 127.0.0.1' ${config.systemd.services.web-desktop-vnc.serviceConfig.ExecStart}
    grep --fixed-strings -- '-rfbport 5910' ${config.systemd.services.web-desktop-vnc.serviceConfig.ExecStart}
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} configuration invariants passed.' > "$out/result"
  ''
