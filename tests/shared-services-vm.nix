{ nixarrModule, sopsModule }:

{
  name = "balaur-shared-services";

  nodes = {
    server =
      { pkgs, ... }:
      {
        imports = [
          nixarrModule
          sopsModule
          ../modules/secrets.nix
          ../modules/networking.nix
          ../modules/home-assistant.nix
          ../modules/media.nix
        ];

        networking = {
          useDHCP = false;
          interfaces.eth1.ipv4.addresses = [
            {
              address = "192.168.50.2";
              prefixLength = 24;
            }
          ];
        };
        balaur.network = {
          trustedInterfaces = [ "eth1" ];
          serverAddress = "192.168.50.2";
          routerAddress = "192.168.50.1";
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
                where = "/srv/services/jellyfin";
                options = "mode=0755,size=4G";
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

        environment.systemPackages = with pkgs; [
          curl
          iproute2
          util-linux
        ];
        virtualisation.memorySize = 3072;
        virtualisation.cores = 2;
      };

    client =
      { pkgs, ... }:
      {
        networking = {
          useDHCP = false;
          interfaces.eth1.ipv4.addresses = [
            {
              address = "192.168.50.3";
              prefixLength = 24;
            }
          ];
        };
        environment.systemPackages = with pkgs; [
          curl
          netcat-openbsd
        ];
      };
  };

  testScript = ''
    server.start()
    client.start()

    server.wait_for_unit("srv-services.mount")
    server.wait_for_unit("srv-services-jellyfin.mount")
    server.wait_for_unit("srv-media.mount")
    server.wait_for_unit("home-assistant.service", timeout=180)
    server.wait_for_unit("jellyfin.service", timeout=180)
    server.wait_for_unit("caddy.service")

    with subtest("Caddy-only Home Assistant and Jellyfin routes"):
        client.wait_until_succeeds(
            "curl --fail --insecure --silent --output /dev/null --resolve home-assistant.home.arpa:443:192.168.50.2 https://home-assistant.home.arpa/"
        )
        client.wait_until_succeeds(
            "curl --fail --insecure --silent --output /dev/null --resolve jellyfin.home.arpa:443:192.168.50.2 https://jellyfin.home.arpa/web/index.html"
        )
        client.fail(
            "curl --fail --insecure --silent --resolve downloads.home.arpa:443:192.168.50.2 https://downloads.home.arpa/"
        )

    with subtest("raw listeners are loopback-only and host firewall ports stay closed"):
        server.succeed("ss -lntH | grep -F '127.0.0.1:8123'")
        server.succeed("ss -lntH | grep -F '127.0.0.1:8096'")
        server.fail("ss -lntH | grep -E '(0.0.0.0|192.168.50.2):(8096|8123)\\b'")
        for port in [8096, 8123, 8082, 6881, 9696]:
            client.fail(f"nc -z -w 1 192.168.50.2 {port}")

    with subtest("disposable Jellyfin mount, permissions, and resource weights"):
        server.succeed("test $(findmnt -n -o FSTYPE --target /srv/services) = tmpfs")
        server.succeed("test $(findmnt -n -o FSTYPE --target /srv/services/jellyfin) = tmpfs")
        server.succeed("test $(findmnt -n -o TARGET --target /srv/services/jellyfin) = /srv/services/jellyfin")
        server.succeed("test $(stat -c '%U:%G:%a' /srv/services/jellyfin/data) = jellyfin:jellyfin:700")
        server.succeed("test $(stat -c '%U:%G:%a' /srv/services/home-assistant) = hass:hass:700")
        server.succeed("printf media > /srv/media/readable; chown alex:media /srv/media/readable; chmod 0640 /srv/media/readable")
        server.succeed("su -s /bin/sh jellyfin -c 'cat /srv/media/readable'")
        server.fail("su -s /bin/sh jellyfin -c 'touch /srv/media/jellyfin-write'")
        server.fail("su -s /bin/sh andreea -c 'touch /srv/media/andreea-write'")
        server.succeed("test $(systemctl show jellyfin -p CPUWeight --value) = 200")
        server.succeed("test $(systemctl show jellyfin -p IOWeight --value) = 200")
        server.succeed("test $(systemctl show jellyfin -p IOSchedulingPriority --value) = 0")

    with subtest("forbidden shared applications and qBittorrent gate are absent"):
        for unit in [
            "qbittorrent.service",
            "qbt.service",
            "qbt-webui-proxy.service",
            "prowlarr.service",
            "sonarr.service",
            "radarr.service",
            "lidarr.service",
            "seerr.service",
        ]:
            server.fail(f"systemctl cat {unit}")

    with subtest("required mounts fail closed without fallback writes"):
        server.succeed("systemctl stop home-assistant.service jellyfin.service")
        server.succeed("systemctl mask --runtime srv-services-jellyfin.mount srv-services.mount")
        server.succeed("umount /srv/services/jellyfin")
        server.succeed("umount /srv/services")
        server.fail("systemctl start home-assistant.service")
        server.fail("systemctl start jellyfin.service")
        server.fail("test -e /srv/services/home-assistant")
        server.fail("test -e /srv/services/jellyfin/data")
  '';
}
