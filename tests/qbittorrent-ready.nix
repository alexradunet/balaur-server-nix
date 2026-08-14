{ config, pkgs }:

let
  inherit (pkgs) lib;
  qbt = config.vpnNamespaces.qbt;
  unit = config.systemd.services.qbittorrent;
  firewallPorts =
    config.networking.firewall.allowedTCPPorts
    ++ config.networking.firewall.allowedUDPPorts
    ++ lib.concatMap (
      interface:
      config.networking.firewall.interfaces.${interface}.allowedTCPPorts
      ++ config.networking.firewall.interfaces.${interface}.allowedUDPPorts
    ) config.balaur.network.trustedInterfaces;
  assertions = [
    {
      assertion =
        config.balaur.sharedServices.qbittorrent.credentials.ready
        && config.services.qbittorrent.enable
        && config.services.qbittorrent.user == "qbittorrent"
        && config.services.qbittorrent.group == "media"
        && config.services.qbittorrent.profileDir == "/srv/services/qbittorrent"
        && config.services.qbittorrent.webuiPort == 8082
        && config.services.qbittorrent.torrentingPort == 6881
        && !config.services.qbittorrent.openFirewall;
      message = "the credential-ready qBittorrent service shape must remain exact";
    }
    {
      assertion =
        qbt.enable
        && qbt.wireguardConfigFile == "/run/balaur-secrets/host/qbittorrent/proton.conf"
        && qbt.accessibleFrom == [ "127.0.0.1" ]
        &&
          qbt.portMappings == [
            {
              from = 8082;
              to = 8082;
              protocol = "tcp";
            }
          ]
        &&
          qbt.openVPNPorts == [
            {
              port = 6881;
              protocol = "both";
            }
          ];
      message = "WebUI mapping and peer ports must exist only in the fail-closed VPN namespace";
    }
    {
      assertion =
        unit.vpnConfinement.enable
        && unit.vpnConfinement.vpnNamespace == "qbt"
        && builtins.elem "qbt.service" unit.bindsTo
        && unit.serviceConfig.NetworkNamespacePath == "/run/netns/qbt"
        &&
          unit.serviceConfig.LoadCredential
          == "webui-password-hash:/run/balaur-secrets/host/qbittorrent/webui-pbkdf2"
        && unit.serviceConfig.CPUWeight == 25
        && unit.serviceConfig.IOWeight == 25
        && unit.serviceConfig.IOSchedulingPriority == 7;
      message = "qBittorrent must bind to the VPN lifecycle, runtime WebUI credential, and low resource weight";
    }
    {
      assertion =
        lib.all (path: builtins.elem path unit.unitConfig.RequiresMountsFor) [
          "/srv/services"
          "/srv/downloads"
          "/srv/media"
        ]
        &&
          unit.unitConfig.ConditionPathIsMountPoint == [
            "/srv/services"
            "/srv/downloads"
            "/srv/media"
          ];
      message = "qBittorrent must fail closed on every state, incomplete, and completed-data mount";
    }
    {
      assertion =
        config.balaur.ingress.reverseProxies."downloads.home.arpa".backend == {
          host = "127.0.0.1";
          port = 8082;
        }
        && lib.hasInfix "bind=127.0.0.1" config.systemd.services.qbt-webui-proxy.serviceConfig.ExecStart
        && lib.hasInfix "192.168.15.1:8082" config.systemd.services.qbt-webui-proxy.serviceConfig.ExecStart;
      message = "downloads ingress must terminate at Caddy and a loopback-only namespace proxy";
    }
    {
      assertion =
        lib.all (port: !builtins.elem port firewallPorts) [
          6881
          8082
        ]
        && !(config.systemd.services.qbt.serviceConfig ? ExecStartPost);
      message = "host firewalls must omit torrent/UI ports and no obsolete Proton DNS route script may remain";
    }
    {
      assertion = lib.all (name: !config.nixarr.${name}.enable) [
        "prowlarr"
        "sonarr"
        "radarr"
        "lidarr"
        "seerr"
      ];
      message = "credential-ready qBittorrent must not imply indexers or media automation";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur credential-ready qBittorrent invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-qbittorrent-ready-tests" { } ''
    mkdir -p "$out"
    printf '%s\n' 'Credential-ready qBittorrent invariants passed.' > "$out/result"
  ''
