{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.balaur.sharedServices.qbittorrent;
  secretRoot = "${config.balaur.secrets.policies.host.runtimeDirectory}/qbittorrent";
  jellyfinState = "/srv/services/jellyfin";
  qbittorrentBaseConfig = pkgs.writeText "qbittorrent-base.conf" ''
    [LegalNotice]
    Accepted=true

    [BitTorrent]
    Session\DefaultSavePath=/srv/media/downloads
    Session\Port=6881
    Session\TempPath=/srv/downloads/incomplete
    Session\TempPathEnabled=true

    [Preferences]
    Downloads\SavePath=/srv/media/downloads
    Downloads\TempPath=/srv/downloads/incomplete
    Downloads\TempPathEnabled=true
    WebUI\Address=192.168.15.1
    WebUI\AuthSubnetWhitelistEnabled=false
    WebUI\CSRFProtection=true
    WebUI\HostHeaderValidation=false
    WebUI\LocalHostAuth=true
    WebUI\Port=8082
    WebUI\Username=alex
  '';
  jellyfinNetworkConfig = pkgs.writeText "jellyfin-network.xml" ''
    <?xml version="1.0" encoding="utf-8"?>
    <NetworkConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
      <BaseUrl />
      <EnableHttps>false</EnableHttps>
      <RequireHttps>false</RequireHttps>
      <InternalHttpPort>8096</InternalHttpPort>
      <InternalHttpsPort>8920</InternalHttpsPort>
      <PublicHttpPort>8096</PublicHttpPort>
      <PublicHttpsPort>8920</PublicHttpsPort>
      <AutoDiscovery>false</AutoDiscovery>
      <EnableIPv4>true</EnableIPv4>
      <EnableIPv6>false</EnableIPv6>
      <EnableRemoteAccess>false</EnableRemoteAccess>
      <LocalNetworkSubnets />
      <LocalNetworkAddresses>
        <string>127.0.0.1</string>
      </LocalNetworkAddresses>
      <KnownProxies>
        <string>127.0.0.1</string>
      </KnownProxies>
      <IgnoreVirtualInterfaces>true</IgnoreVirtualInterfaces>
      <VirtualInterfaceNames>
        <string>veth</string>
      </VirtualInterfaceNames>
      <EnablePublishedServerUriByRequest>false</EnablePublishedServerUriByRequest>
      <PublishedServerUriBySubnet />
      <RemoteIPFilter />
      <IsRemoteIPFilterBlacklist>false</IsRemoteIPFilterBlacklist>
    </NetworkConfiguration>
  '';
in
{
  options.balaur.sharedServices.qbittorrent.credentials = {
    ready = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Human-controlled production gate. Keep false until both the Proton
        WireGuard configuration and qBittorrent WebUI PBKDF2 value are supplied
        by reviewed host-authority sops declarations.
      '';
    };

    wireguardConfigFile = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.strMatching "^/run/balaur-secrets/host/qbittorrent/[a-zA-Z0-9._-]+$"
      );
      default = null;
      description = "Runtime-only Proton WireGuard wg-quick configuration file.";
    };

    webuiPasswordHashFile = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.strMatching "^/run/balaur-secrets/host/qbittorrent/[a-zA-Z0-9._-]+$"
      );
      default = null;
      description = "Runtime-only file containing qBittorrent's serialized PBKDF2 WebUI value.";
    };
  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion =
            !cfg.credentials.ready
            || (
              cfg.credentials.wireguardConfigFile != null
              && cfg.credentials.webuiPasswordHashFile != null
              && lib.hasPrefix "${secretRoot}/" cfg.credentials.wireguardConfigFile
              && lib.hasPrefix "${secretRoot}/" cfg.credentials.webuiPasswordHashFile
              && cfg.credentials.wireguardConfigFile != cfg.credentials.webuiPasswordHashFile
            );
          message = "Enabling qBittorrent requires distinct Proton and WebUI runtime files below the host qBittorrent secret root";
        }
        {
          assertion =
            !config.nixarr.prowlarr.enable
            && !config.nixarr.sonarr.enable
            && !config.nixarr.radarr.enable
            && !config.nixarr.lidarr.enable
            && !config.nixarr.seerr.enable;
          message = "Issue 09 must not enable media automation or indexer applications";
        }
      ];

      warnings = lib.optional (!cfg.credentials.ready) ''
        DEPLOYMENT BLOCKER: qBittorrent is fail-closed because balaur.sharedServices.qbittorrent.credentials.ready is false. Supply reviewed sops-backed Proton WireGuard and WebUI PBKDF2 runtime files before enabling it.
      '';

      hardware.graphics.enable = true;

      services.jellyfin = {
        enable = true;
        openFirewall = false;
        dataDir = "${jellyfinState}/data";
        configDir = "${jellyfinState}/config";
        cacheDir = "${jellyfinState}/cache";
        logDir = "${jellyfinState}/log";
        hardwareAcceleration = {
          enable = true;
          type = "vaapi";
          device = "/dev/dri/renderD128";
        };
      };

      users.users = lib.mkIf config.services.jellyfin.enable {
        jellyfin.extraGroups = [
          "media"
          "render"
          "video"
        ];
      };

      balaur.ingress.reverseProxies."jellyfin.home.arpa" = {
        backend = {
          host = "127.0.0.1";
          port = 8096;
        };
      };

      systemd.services = {
        jellyfin-storage = {
          description = "Prepare mounted disposable Jellyfin state";
          before = [ "jellyfin.service" ];
          requiredBy = [ "jellyfin.service" ];
          unitConfig = {
            RequiresMountsFor = [
              jellyfinState
              "/srv/media"
            ];
            ConditionPathIsMountPoint = [
              jellyfinState
              "/srv/media"
            ];
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            for directory in data config cache log; do
              install -d -m 0700 -o jellyfin -g jellyfin ${jellyfinState}/$directory
            done
          '';
        };

        jellyfin = {
          requires = [ "jellyfin-storage.service" ];
          after = [ "jellyfin-storage.service" ];
          preStart = lib.mkBefore ''
            install -m 0600 ${jellyfinNetworkConfig} ${jellyfinState}/config/network.xml
          '';
          unitConfig = {
            RequiresMountsFor = [
              jellyfinState
              "/srv/media"
            ];
            ConditionPathIsMountPoint = [
              jellyfinState
              "/srv/media"
            ];
          };
          serviceConfig = {
            CPUWeight = 200;
            IOWeight = 200;
            IOSchedulingPriority = 0;
            PrivateDevices = true;
            DeviceAllow = lib.mkAfter [ "char-drm rw" ];
          };
        };
      };
    }

    (lib.mkIf cfg.credentials.ready {
      users.users.qbittorrent = {
        isSystemUser = true;
        group = "media";
      };

      services.qbittorrent = {
        enable = true;
        user = "qbittorrent";
        group = "media";
        profileDir = "/srv/services/qbittorrent";
        openFirewall = false;
        webuiPort = 8082;
        torrentingPort = 6881;
      };

      vpnNamespaces.qbt = {
        enable = true;
        wireguardConfigFile = cfg.credentials.wireguardConfigFile;
        # Keeping this to loopback avoids the pinned module's 10.0.0.0/8
        # bridge route, so Proton DNS such as 10.2.0.1 follows wg0 naturally.
        accessibleFrom = [ "127.0.0.1" ];
        portMappings = [
          {
            from = 8082;
            to = 8082;
            protocol = "tcp";
          }
        ];
        openVPNPorts = [
          {
            port = 6881;
            protocol = "both";
          }
        ];
      };

      balaur.ingress.reverseProxies."downloads.home.arpa" = {
        backend = {
          host = "127.0.0.1";
          port = 8082;
        };
      };

      systemd.services = {
        qbittorrent-storage = {
          description = "Prepare mounted qBittorrent state";
          before = [ "qbittorrent.service" ];
          requiredBy = [ "qbittorrent.service" ];
          unitConfig = {
            RequiresMountsFor = [ "/srv/services" ];
            ConditionPathIsMountPoint = [ "/srv/services" ];
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            install -d -m 0750 -o qbittorrent -g media /srv/services/qbittorrent/qBittorrent/config
          '';
        };

        qbittorrent-media-permissions = {
          description = "Apply controlled qBittorrent media permissions";
          before = [ "qbittorrent.service" ];
          requiredBy = [ "qbittorrent.service" ];
          unitConfig = {
            RequiresMountsFor = [
              "/srv/downloads"
              "/srv/media"
            ];
            ConditionPathIsMountPoint = [
              "/srv/downloads"
              "/srv/media"
            ];
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            install -d -m 0700 -o qbittorrent -g media /srv/downloads/incomplete
            install -d -m 2750 -o qbittorrent -g media /srv/media/downloads
            ${pkgs.acl}/bin/setfacl -m u:alex:rwx,m:rwx,d:u:alex:rwx,d:g:media:r-x,d:m:rwx /srv/media/downloads
          '';
        };

        qbittorrent = {
          requires = [
            "qbittorrent-storage.service"
            "qbittorrent-media-permissions.service"
          ];
          after = [
            "qbittorrent-storage.service"
            "qbittorrent-media-permissions.service"
          ];
          vpnConfinement = {
            enable = true;
            vpnNamespace = "qbt";
          };
          unitConfig = {
            RequiresMountsFor = [
              "/srv/services"
              "/srv/downloads"
              "/srv/media"
            ];
            ConditionPathIsMountPoint = [
              "/srv/services"
              "/srv/downloads"
              "/srv/media"
            ];
          };
          preStart = ''
            hash="$(${pkgs.coreutils}/bin/tr -d '\n' < "$CREDENTIALS_DIRECTORY/webui-password-hash")"
            ${pkgs.coreutils}/bin/printf '%s\n' "$hash" | ${pkgs.gnugrep}/bin/grep -Eq "^@ByteArray\\('[A-Za-z0-9+/=]+:[A-Za-z0-9+/=]+'\\)$"
            config=/srv/services/qbittorrent/qBittorrent/config/qBittorrent.conf
            ${pkgs.coreutils}/bin/install -Dm0600 ${qbittorrentBaseConfig} "$config"
            ${pkgs.gawk}/bin/awk -v value="$hash" '
              $0 == "[Preferences]" {
                print
                print "WebUI\\Password_PBKDF2=" value
                found = 1
                next
              }
              $0 !~ /^WebUI\\Password_PBKDF2=/ { print }
              END { if (!found) exit 1 }
            ' "$config" > "$config.tmp"
            ${pkgs.coreutils}/bin/install -m 0600 "$config.tmp" "$config"
            ${pkgs.coreutils}/bin/rm -f "$config.tmp"
          '';
          serviceConfig = {
            CPUWeight = 25;
            IOWeight = 25;
            IOSchedulingPriority = 7;
            UMask = "0007";
            LoadCredential = "webui-password-hash:${cfg.credentials.webuiPasswordHashFile}";
          };
        };

        qbt-webui-proxy = {
          description = "Loopback proxy for the VPN-confined qBittorrent WebUI";
          requires = [ "qbittorrent.service" ];
          after = [ "qbittorrent.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            User = "qbittorrent";
            Group = "media";
            Restart = "on-failure";
            RestartSec = 5;
            ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:8082,bind=127.0.0.1,reuseaddr,fork TCP:192.168.15.1:8082";
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateTmp = true;
            ProtectHome = true;
            ProtectSystem = "strict";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_UNIX"
            ];
          };
        };
      };
    })
  ];
}
