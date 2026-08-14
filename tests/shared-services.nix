{ config, pkgs }:

let
  inherit (pkgs) lib;
  serviceNames = builtins.attrNames config.systemd.services;
  firewallPorts =
    config.networking.firewall.allowedTCPPorts
    ++ config.networking.firewall.allowedUDPPorts
    ++ lib.concatMap (
      interface:
      config.networking.firewall.interfaces.${interface}.allowedTCPPorts
      ++ config.networking.firewall.interfaces.${interface}.allowedUDPPorts
    ) config.balaur.network.trustedInterfaces;
  forbiddenServices = [
    "balaur-dashboard"
    "llama-server"
    "prowlarr"
    "prowlarr-qbittorrent-sync"
    "qbittorrent"
    "qbt"
    "qbt-webui-proxy"
    "radarr"
    "sonarr"
    "lidarr"
    "seerr"
  ];
  jellyfinUnit = config.systemd.services.jellyfin;
  homeAssistantUnit = config.systemd.services.home-assistant;
  expectedRoutes = {
    "home-assistant.home.arpa".backend = {
      host = "127.0.0.1";
      port = 8123;
    };
    "jellyfin.home.arpa".backend = {
      host = "127.0.0.1";
      port = 8096;
    };
  };
  assertions = [
    {
      assertion =
        config.services.home-assistant.enable
        && config.services.home-assistant.configDir == "/srv/services/home-assistant"
        && config.services.home-assistant.config.http.server_host == "127.0.0.1"
        && config.services.home-assistant.config.http.server_port == 8123
        && config.services.home-assistant.config.http.use_x_forwarded_for
        && config.services.home-assistant.config.http.trusted_proxies == [ "127.0.0.1" ]
        && !config.services.home-assistant.openFirewall
        && !config.services.home-assistant.openFirewallForComponents
        && config.hardware.bluetooth.enable
        && lib.all (
          interface:
          builtins.elem 1900 config.networking.firewall.interfaces.${interface}.allowedUDPPorts
          && builtins.elem 5353 config.networking.firewall.interfaces.${interface}.allowedUDPPorts
        ) config.balaur.network.trustedInterfaces;
      message = "Home Assistant must be fresh under protected service storage, retain local discovery, and listen only on loopback behind Caddy";
    }
    {
      assertion =
        builtins.elem "/srv/services" homeAssistantUnit.unitConfig.RequiresMountsFor
        && homeAssistantUnit.unitConfig.ConditionPathIsMountPoint == [ "/srv/services" ];
      message = "Home Assistant must fail closed when protected service storage is not mounted";
    }
    {
      assertion =
        config.services.jellyfin.enable
        && config.services.jellyfin.dataDir == "/srv/services/jellyfin/data"
        && config.services.jellyfin.configDir == "/srv/services/jellyfin/config"
        && config.services.jellyfin.cacheDir == "/srv/services/jellyfin/cache"
        && config.services.jellyfin.logDir == "/srv/services/jellyfin/log"
        && !config.services.jellyfin.openFirewall
        && config.services.jellyfin.hardwareAcceleration.enable
        && config.services.jellyfin.hardwareAcceleration.type == "vaapi"
        && config.services.jellyfin.hardwareAcceleration.device == "/dev/dri/renderD128"
        && builtins.elem "media" config.users.users.jellyfin.extraGroups
        && builtins.elem "render" config.users.users.jellyfin.extraGroups
        && builtins.elem "video" config.users.users.jellyfin.extraGroups;
      message = "Jellyfin must use disposable state, shared media, and the Radeon render/video access policy";
    }
    {
      assertion =
        lib.all (path: builtins.elem path jellyfinUnit.unitConfig.RequiresMountsFor) [
          "/srv/services/jellyfin"
          "/srv/media"
        ]
        &&
          jellyfinUnit.unitConfig.ConditionPathIsMountPoint == [
            "/srv/services/jellyfin"
            "/srv/media"
          ]
        && jellyfinUnit.serviceConfig.CPUWeight == 200
        && jellyfinUnit.serviceConfig.IOWeight == 200
        && jellyfinUnit.serviceConfig.IOSchedulingPriority == 0
        && jellyfinUnit.serviceConfig.PrivateDevices
        && builtins.elem "/dev/dri/renderD128 rw" jellyfinUnit.serviceConfig.DeviceAllow
        && builtins.elem "char-drm rw" jellyfinUnit.serviceConfig.DeviceAllow;
      message = "Jellyfin mounts, hardware device sandbox, and CPU/IO priority must be explicit";
    }
    {
      assertion =
        config.balaur.storage.disposableDatasets == [
          "tank/disposable/media"
          "tank/disposable/jellyfin"
          "tank/disposable/downloads"
          "tank/disposable/models"
          "tank/disposable/cache"
          "tank/disposable/temp"
        ]
        && !(builtins.elem "tank/disposable/jellyfin" config.balaur.storage.protectedLeafDatasets)
        && config.fileSystems."/srv/services/jellyfin".device == "tank/disposable/jellyfin";
      message = "Jellyfin metadata and watch state must live on an explicit disposable nested ZFS mount";
    }
    {
      assertion = config.balaur.ingress.reverseProxies == expectedRoutes;
      message = "only Home Assistant and Jellyfin may register production shared-service routes before qBittorrent credentials exist";
    }
    {
      assertion =
        !config.balaur.sharedServices.qbittorrent.credentials.ready
        && config.balaur.sharedServices.qbittorrent.credentials.wireguardConfigFile == null
        && config.balaur.sharedServices.qbittorrent.credentials.webuiPasswordHashFile == null
        && !(config.balaur.ingress.reverseProxies ? "downloads.home.arpa")
        && !(config.vpnNamespaces ? qbt)
        && lib.any (warning: lib.hasInfix "qBittorrent is fail-closed" warning) config.warnings;
      message = "qBittorrent, its VPN namespace, and its UI route must remain absent until both real runtime credentials are ready";
    }
    {
      assertion = lib.all (service: !builtins.elem service serviceNames) forbiddenServices;
      message = "qBittorrent, llama, dashboard, indexer, and media-automation units must remain absent in credential-blocked production";
    }
    {
      assertion = lib.all (port: !builtins.elem port firewallPorts) [
        6881
        8082
        8096
        8123
        9696
      ];
      message = "raw application and torrent peer ports must remain closed on every host firewall surface";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur shared-service invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-shared-services-tests" { } ''
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} shared-service invariants passed.' > "$out/result"
  ''
