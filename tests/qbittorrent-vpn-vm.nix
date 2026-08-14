{
  nixarrModule,
  sopsModule,
}:

{
  pkgs,
  lib,
  ...
}:

let
  wgPort = 51820;
  gatewayPrivate =
    pkgs.runCommand "test-wg-gateway-private" { nativeBuildInputs = [ pkgs.wireguard-tools ]; }
      ''
        wg genkey > $out
      '';
  gatewayPublic =
    pkgs.runCommand "test-wg-gateway-public" { nativeBuildInputs = [ pkgs.wireguard-tools ]; }
      ''
        wg pubkey < ${gatewayPrivate} > $out
      '';
  clientPrivate =
    pkgs.runCommand "test-wg-client-private" { nativeBuildInputs = [ pkgs.wireguard-tools ]; }
      ''
        wg genkey > $out
      '';
  clientPublic =
    pkgs.runCommand "test-wg-client-public" { nativeBuildInputs = [ pkgs.wireguard-tools ]; }
      ''
        wg pubkey < ${clientPrivate} > $out
      '';
  clientConfig = pkgs.writeText "synthetic-proton.conf" ''
    [Interface]
    PrivateKey = ${builtins.readFile clientPrivate}
    Address = 10.100.0.2/24
    DNS = 10.100.0.1

    [Peer]
    PublicKey = ${builtins.readFile gatewayPublic}
    Endpoint = 192.168.60.1:${toString wgPort}
    AllowedIPs = 0.0.0.0/0
    PersistentKeepalive = 1
  '';
in
{
  name = "balaur-qbittorrent-vpn-fail-closed";

  nodes = {
    gateway =
      { pkgs, ... }:
      {
        networking = {
          useDHCP = false;
          interfaces.eth1.ipv4.addresses = [
            {
              address = "192.168.60.1";
              prefixLength = 24;
            }
          ];
          firewall = {
            allowedUDPPorts = [ wgPort ];
            interfaces = {
              eth1.allowedTCPPorts = [ 18080 ];
              wg0.allowedTCPPorts = [ 18080 ];
            };
          };
          wireguard.interfaces.wg0 = {
            ips = [ "10.100.0.1/24" ];
            listenPort = wgPort;
            privateKeyFile = "${gatewayPrivate}";
            peers = [
              {
                publicKey = builtins.readFile clientPublic;
                allowedIPs = [ "10.100.0.2/32" ];
              }
            ];
          };
        };

        systemd.services.synthetic-tracker = {
          wantedBy = [ "multi-user.target" ];
          after = [ "wireguard-wg0.service" ];
          serviceConfig.ExecStart = "${pkgs.python3}/bin/python3 -m http.server 18080 --bind 0.0.0.0";
        };

        environment.systemPackages = with pkgs; [
          curl
          iptables
          netcat-openbsd
        ];
      };

    server =
      { pkgs, lib, ... }:
      {
        imports = [
          nixarrModule
          sopsModule
          ../modules/secrets.nix
          ../modules/networking.nix
          ../modules/home-assistant.nix
          ../modules/media.nix
        ];

        services.home-assistant.enable = lib.mkForce false;
        services.jellyfin.enable = lib.mkForce false;

        networking = {
          useDHCP = false;
          defaultGateway = {
            address = "192.168.60.1";
            interface = "eth1";
          };
          interfaces.eth1.ipv4.addresses = [
            {
              address = "192.168.60.2";
              prefixLength = 24;
            }
          ];
        };
        balaur.network = {
          trustedInterfaces = [ "eth1" ];
          serverAddress = "192.168.60.2";
          routerAddress = "192.168.60.1";
        };
        balaur.sharedServices.qbittorrent.credentials = {
          ready = true;
          wireguardConfigFile = "/run/balaur-secrets/host/qbittorrent/proton.conf";
          webuiPasswordHashFile = "/run/balaur-secrets/host/qbittorrent/webui-pbkdf2";
        };

        users.users = {
          alex = {
            isNormalUser = true;
            group = "users";
          };
          andreea = {
            isNormalUser = true;
            group = "users";
            hashedPassword = "!";
            shell = "${pkgs.shadow}/bin/nologin";
          };
        };

        systemd.mounts =
          map
            (mount: {
              what = "tmpfs";
              inherit (mount) where;
              type = "tmpfs";
              options = mount.options;
              wantedBy = [ "local-fs.target" ];
            })
            [
              {
                where = "/srv/services";
                options = "mode=0755";
              }
              {
                where = "/srv/media";
                options = "mode=0750";
              }
              {
                where = "/srv/downloads";
                options = "mode=0700";
              }
            ];

        systemd.services = {
          synthetic-qbittorrent-secrets = {
            before = [ "qbt.service" ];
            requiredBy = [ "qbt.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              UMask = "0077";
            };
            script = ''
              install -d -m 0700 /run/balaur-secrets/host/qbittorrent
              install -m 0600 ${clientConfig} /run/balaur-secrets/host/qbittorrent/proton.conf
              printf '%s\n' "@ByteArray('YWJjZA==:ZWZnaA==')" > /run/balaur-secrets/host/qbittorrent/webui-pbkdf2
            '';
          };
          qbt = {
            requires = [ "synthetic-qbittorrent-secrets.service" ];
            after = [ "synthetic-qbittorrent-secrets.service" ];
          };
        };

        environment.systemPackages = with pkgs; [
          curl
          iproute2
          netcat-openbsd
        ];
        virtualisation.memorySize = 1536;
      };
  };

  testScript = ''
    gateway.start()
    gateway.wait_for_unit("wireguard-wg0.service")
    gateway.wait_for_unit("synthetic-tracker.service")
    server.start()
    server.wait_for_unit("qbt.service", timeout=120)
    server.wait_for_unit("qbittorrent.service", timeout=120)
    server.wait_for_unit("qbt-webui-proxy.service", timeout=120)
    server.wait_for_unit("caddy.service")

    with subtest("qBittorrent and peer sockets are confined to the VPN namespace"):
        server.succeed("ip netns exec qbt curl --fail --silent http://10.100.0.1:18080/ >/dev/null")
        server.succeed("ip netns exec qbt ss -lnt | grep -F ':6881'")
        server.succeed("ip netns exec qbt ss -lnu | grep -F ':6881'")
        server.fail("ss -lntup | grep -E '0.0.0.0:(6881|8082)\\b'")
        gateway.fail("nc -z -w 1 192.168.60.2 6881")
        gateway.fail("nc -z -w 1 192.168.60.2 8082")
        gateway.succeed("curl --fail --insecure --silent --resolve downloads.home.arpa:443:192.168.60.2 https://downloads.home.arpa/ | grep -F qBittorrent")
        gateway.fail("curl --fail --insecure --silent --resolve downloads.home.arpa:443:192.168.60.2 https://downloads.home.arpa/api/v2/app/version")

    with subtest("WireGuard interruption blocks tracker egress while approved UI survives"):
        gateway.succeed("iptables -I INPUT -p udp --dport ${toString wgPort} -j DROP")
        gateway.succeed("iptables -I OUTPUT -p udp --sport ${toString wgPort} -j DROP")
        server.fail("ip netns exec qbt ping -c 1 -W 3 10.100.0.1")
        server.fail("ip netns exec qbt curl --fail --silent --max-time 3 http://10.100.0.1:18080/")
        server.succeed("curl --fail --silent --max-time 3 http://192.168.60.1:18080/ >/dev/null")
        gateway.succeed("curl --fail --insecure --silent --output /dev/null --resolve downloads.home.arpa:443:192.168.60.2 https://downloads.home.arpa/")
        server.succeed("systemctl is-active qbittorrent.service qbt-webui-proxy.service")
  '';
}
