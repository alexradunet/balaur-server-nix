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
          == "/dev/disk/by-label/BALAUR_BACKUP"
        && lib.all (
          mount: builtins.elem mount config.systemd.services.balaur-backup.unitConfig.RequiresMountsFor
        ) [
          "/srv/app-data"
          "/srv/personal"
        ];
      message = "the encrypted USB backup must remain offline by default and use protected credentials";
    }
    {
      assertion =
        config.services.trilium-server.enable
        && config.services.trilium-server.package.version == "0.104.1"
        && config.services.trilium-server.dataDir == "/srv/app-data/trilium"
        && config.services.trilium-server.instanceName == "Trilium"
        && !config.services.trilium-server.noBackup
        && !config.services.trilium-server.noAuthentication
        && config.services.trilium-server.host == "127.0.0.1"
        && config.services.trilium-server.port == 11000
        && config.systemd.services.trilium-server.unitConfig.RequiresMountsFor == [ "/srv/app-data" ]
        && config.systemd.services.trilium-server.serviceConfig.NoNewPrivileges
        && config.systemd.services.trilium-server.serviceConfig.ProtectSystem == "strict"
        && config.systemd.services.trilium-server.serviceConfig.ReadWritePaths == [ "/srv/app-data/trilium" ]
        && config.systemd.services.trilium-server.environment.TRILIUM_NETWORK_TRUSTEDREVERSEPROXY == "127.0.0.1"
        && lib.hasInfix
          "reverse_proxy 127.0.0.1:11000"
          config.services.caddy.virtualHosts."https://192.168.50.2:8084".extraConfig
        && lib.hasInfix
          "tls internal"
          config.services.caddy.virtualHosts."https://192.168.50.2:8084".extraConfig
        && lib.hasInfix
          "reverse_proxy 127.0.0.1:11000"
          config.services.caddy.virtualHosts."http://192.168.50.2:8085".extraConfig

        && !config.services.nextcloud.enable
        && !config.services.postgresql.enable
        && !(config.services.redis.servers ? nextcloud)
        && !config.services.nginx.enable
        && !(config.fileSystems ? "/srv/app-data/nextcloud/data")
        && !builtins.any (
          package: lib.getName package == "obsidian"
        ) config.environment.systemPackages
        && !builtins.elem 11000 config.networking.firewall.interfaces.enp100s0.allowedTCPPorts;
      message = "Trilium must replace the Nextcloud stack behind the existing LAN endpoint";
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
          8081
          8082
          8084
          8085
          8096
          8123
          9696
        ]
        && config.networking.firewall.interfaces.enp100s0.allowedUDPPorts == [ ]
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
        && !config.services.syncthing.enable
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
        && lib.all (service: config.nixarr.${service}.enable) [
          "jellyfin"
          "prowlarr"
          "qbittorrent"
        ]
        && !config.nixarr.sonarr.enable
        && !config.nixarr.radarr.enable
        && !config.nixarr.prowlarr.settings-sync.enable-nixarr-apps
        && !config.nixarr.lidarr.enable
        && !config.services.seerr.enable
        && config.nixarr.jellyfin.stateDir == "/srv/app-data/jellyfin"
        && config.services.jellyfin.dataDir == "/srv/app-data/jellyfin"
        && config.services.jellyfin.configDir == "/srv/app-data/jellyfin/config"
        && config.services.jellyfin.logDir == "/srv/app-data/jellyfin/log"
        && config.nixarr.prowlarr.stateDir == "/srv/app-data/prowlarr"
        && !config.systemd.services.prowlarr.serviceConfig.DynamicUser
        && config.services.prowlarr.settings.auth.required == "DisabledForLocalAddresses"
        && config.services.qbittorrent.profileDir == "/srv/app-data/qbittorrent"
        && !builtins.elem
          "d /srv/media/ssd0/downloads/complete/manual 2775 qbittorrent media -"
          config.systemd.tmpfiles.rules
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
        && config.systemd.services.prowlarr-qbittorrent-sync.serviceConfig.CapabilityBoundingSet == ""
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
        && builtins.elem "qbt-webui-proxy.service" config.systemd.services.prowlarr-qbittorrent-sync.after
        && builtins.elem "prowlarr.service" config.systemd.services.prowlarr-qbittorrent-sync.after
        && config.systemd.services.prowlarr-qbittorrent-sync.serviceConfig.TimeoutStartSec == 240
        && config.systemd.services.prowlarr-qbittorrent-sync.serviceConfig.LoadCredential == [
          "qbittorrent-password:/srv/secrets/qbittorrent-webui-password"
          "prowlarr-config:/srv/app-data/prowlarr/config.xml"
        ]
        && lib.all (
          entry: builtins.elem entry.mount config.systemd.services.${entry.service}.unitConfig.RequiresMountsFor
        ) [
          { service = "jellyfin"; mount = "/srv/media/ssd0"; }
          { service = "jellyfin"; mount = "/srv/media/ssd1"; }
          { service = "prowlarr"; mount = "/srv/app-data"; }
          { service = "qbittorrent"; mount = "/srv/media/ssd0"; }
        ]
        && !builtins.elem
          "/srv/media/ssd1"
          config.systemd.services.qbittorrent.unitConfig.RequiresMountsFor
        && lib.all (user: config.users.users.${user}.group == "media") [
          "jellyfin"
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
        && config.systemd.services.balaur-dashboard.environment.DASHBOARD_HOST == "127.0.0.1"
        && config.systemd.services.balaur-dashboard.environment.DASHBOARD_PORT == "8080"
        && config.services.caddy.enable
        && lib.hasInfix "reverse_proxy 127.0.0.1:8080" config.services.caddy.virtualHosts."http://192.168.50.2".extraConfig
        && !(builtins.hasAttr "herdr-web" config.systemd.services)
        && !(builtins.hasAttr "web-desktop-novnc" config.systemd.services);
      message = "application access controls and dashboard routing must remain stable";
    }
    {
      assertion = lib.all hardened [
        "prowlarr-qbittorrent-sync"
        "balaur-dashboard"
        "trilium-server"
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
    grep --fixed-strings -- 'stop_if_active trilium-server.service' ${config.systemd.services.balaur-backup.serviceConfig.ExecStart}
    ! grep --fixed-strings -- 'nextcloud' ${config.systemd.services.balaur-backup.serviceConfig.ExecStart}
    ! grep --fixed-strings -- 'pg_dump' ${config.systemd.services.balaur-backup.serviceConfig.ExecStart}
    ! grep --fixed-strings -- 'syncthing.service' ${config.systemd.services.balaur-backup.serviceConfig.ExecStart}
    grep --fixed-strings -- '/var/lib/hass' ${config.systemd.services.balaur-backup.serviceConfig.ExecStart}
    grep --fixed-strings -- 'systemctl restart qbittorrent.service' ${config.systemd.services.prowlarr-qbittorrent-sync.serviceConfig.ExecStart}
    grep --fixed-strings -- '--sync-category' ${config.systemd.services.prowlarr-qbittorrent-sync.serviceConfig.ExecStart}
    grep --fixed-strings -- '"Accept-Encoding": "gzip"' ${../prowlarr-qbittorrent-sync.py}
    grep --fixed-strings -- 'CATEGORY = "manual"' ${../prowlarr-qbittorrent-sync.py}
    grep --fixed-strings -- 'CATEGORY_PATH = "/srv/media/ssd0/downloads/complete"' ${../prowlarr-qbittorrent-sync.py}
    ${pkgs.python3}/bin/python ${../prowlarr-qbittorrent-sync.py} --help >/dev/null
    grep --fixed-strings -- '-interface 127.0.0.1' ${config.systemd.services.web-desktop-vnc.serviceConfig.ExecStart}
    grep --fixed-strings -- '-rfbport 5910' ${config.systemd.services.web-desktop-vnc.serviceConfig.ExecStart}
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} configuration invariants passed.' > "$out/result"
  ''
