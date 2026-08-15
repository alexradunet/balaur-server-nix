{
  name = "balaur-private-network-access";

  nodes = {
    router =
      { pkgs, ... }:
      {
        networking = {
          useDHCP = false;
          interfaces.eth1.ipv4.addresses = [
            {
              address = "192.168.50.1";
              prefixLength = 24;
            }
          ];
          firewall.interfaces.eth1 = {
            allowedTCPPorts = [ 53 ];
            allowedUDPPorts = [ 53 ];
          };
        };
        services.coredns = {
          enable = true;
          config = ''
            .:53 {
              bind 192.168.50.1
              hosts {
                203.0.113.9 forwarded.example
              }
              errors
            }
          '';
        };
      };

    server =
      {
        lib,
        pkgs,
        ...
      }:
      {
        imports = [ ../modules/networking.nix ];

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
        balaur.samba.credentials = {
          ready = true;
          passwordFiles = {
            alex = "/run/balaur-secrets/host/samba/alex-password";
            andreea = "/run/balaur-secrets/host/samba/andreea-password";
          };
        };

        users = {
          mutableUsers = false;
          users = {
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
        };

        systemd.services = {
          test-samba-passwords = {
            description = "Generate disposable VM-only Samba passwords";
            before = [ "samba-credentials.service" ];
            requiredBy = [ "samba-credentials.service" ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              UMask = "0077";
            };
            script = ''
              install -d -m 0700 /run/balaur-secrets/host/samba
              ${pkgs.openssl}/bin/openssl rand -hex 24 > /run/balaur-secrets/host/samba/alex-password
              ${pkgs.openssl}/bin/openssl rand -hex 24 > /run/balaur-secrets/host/samba/andreea-password
            '';
          };
          samba-credentials = {
            requires = [ "test-samba-passwords.service" ];
            after = [ "test-samba-passwords.service" ];
          };
        };

        environment.systemPackages = with pkgs; [
          curl
          dnsutils
          iproute2
          samba
        ];

        virtualisation.memorySize = 1536;
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
          dnsutils
          netcat-openbsd
          samba
        ];
      };
  };

  testScript = ''
    import base64

    router.start()
    router.wait_for_unit("coredns.service")
    server.start()
    client.start()

    server.wait_for_unit("coredns.service")
    server.wait_for_unit("caddy.service")
    server.wait_for_unit("samba-smbd.service")
    for port in [53, 80, 443, 445]:
        client.wait_until_succeeds(f"nc -z -w 1 192.168.50.2 {port}")

    with subtest("authoritative household DNS and deterministic forwarding"):
        names = [
            "balaur.home.arpa",
            "notes.alex.home.arpa",
            "paperless.alex.home.arpa",
            "budget.alex.home.arpa",
            "chat.alex.home.arpa",
            "importer.alex.home.arpa",
            "notes.andreea.home.arpa",
            "paperless.andreea.home.arpa",
            "budget.andreea.home.arpa",
            "chat.andreea.home.arpa",
            "importer.andreea.home.arpa",
            "home-assistant.home.arpa",
            "jellyfin.home.arpa",
            "downloads.home.arpa",
        ]
        for name in names:
            client.succeed(
                f"test \"$(dig @192.168.50.2 {name} A +short)\" = 192.168.50.2"
            )
        client.succeed(
            "dig @192.168.50.2 missing.home.arpa A +noall +comments | grep -F 'status: NXDOMAIN'"
        )
        client.succeed(
            "test \"$(dig @192.168.50.2 forwarded.example A +short)\" = 203.0.113.9"
        )
        server.fail("grep -F 'log' /etc/systemd/system/coredns.service")

    with subtest("Caddy internal CA TLS and health"):
        server.succeed(
            "test \"$(curl --fail --silent --cacert /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt --resolve balaur.home.arpa:443:192.168.50.2 https://balaur.home.arpa/health)\" = 'balaur ok'"
        )
        client.succeed(
            "test \"$(curl --fail --insecure --silent --resolve balaur.home.arpa:443:192.168.50.2 https://balaur.home.arpa/health)\" = 'balaur ok'"
        )
        client.succeed(
            "curl --silent --head --resolve balaur.home.arpa:80:192.168.50.2 http://balaur.home.arpa/health | grep -F 'Location: https://balaur.home.arpa/health'"
        )
        client.fail(
            "curl --fail --insecure --silent --resolve notes.alex.home.arpa:443:192.168.50.2 https://notes.alex.home.arpa/"
        )

    with subtest("listeners and raw application ports"):
        server.succeed("ss -lntH | grep -F '192.168.50.2:53'")
        server.succeed("ss -lnuH | grep -F '192.168.50.2:53'")
        server.succeed("ss -lntH | grep -F '192.168.50.2:80'")
        server.succeed("ss -lntH | grep -F '192.168.50.2:443'")
        server.succeed("ss -lntH | grep -F '192.168.50.2:445'")
        server.fail("ss -lntup | grep -E ':(137|138|139|2019|8080|8081|8082|8084|8085|8096|8123|9696|11000)\\b'")
        server.fail("ss -lnuH | grep -F ':443 '")
        for port in [53, 80, 443, 445]:
            client.succeed(f"nc -z -w 2 192.168.50.2 {port}")
        for port in [139, 8080, 8081, 8082, 8084, 8085, 8096, 8123, 9696, 11000]:
            client.fail(f"nc -z -w 1 192.168.50.2 {port}")

    with subtest("prepare exact share roots"):
        server.succeed("printf 'alex private\\n' > /home/alex/files/private.txt")
        server.succeed("printf 'outside share\\n' > /home/alex/not-exported.txt")
        server.succeed("printf 'andreea private\\n' > /home/andreea/files/private.txt")
        server.succeed("install -d -m 0700 /srv/people/alex/apps /srv/people/andreea/apps")
        server.succeed("printf 'app secret\\n' > /srv/people/alex/apps/not-exported.txt")
        server.succeed("printf 'shared media\\n' > /srv/media/shared.txt")
        server.succeed("chown -R alex:users /home/alex")
        server.succeed("chown -R andreea:users /home/andreea")
        server.succeed("chown -R alex:media /srv/media; chmod 2750 /srv/media")

        alex_password = server.succeed(
            "cat /run/balaur-secrets/host/samba/alex-password"
        ).strip()
        andreea_password = server.succeed(
            "cat /run/balaur-secrets/host/samba/andreea-password"
        ).strip()

        def install_auth(path, username, password):
            body = f"username={username}\npassword={password}\n"
            encoded = base64.b64encode(body.encode()).decode()
            client.succeed(
                f"printf %s {encoded} | base64 -d > {path}; chmod 0600 {path}"
            )

        install_auth("/run/alex.auth", "alex", alex_password)
        install_auth("/run/andreea.auth", "andreea", andreea_password)
        client.succeed("printf 'alex upload\\n' > /tmp/alex-upload.txt")
        client.succeed("printf 'andreea upload\\n' > /tmp/andreea-upload.txt")

    with subtest("no guest, SMB1, full-home, app, or extra exports"):
        client.fail("smbclient //192.168.50.2/media -N -c ls")
        client.fail("smbclient //192.168.50.2/media -A /run/alex.auth -m NT1 -c ls")
        shares = client.succeed(
            "smbclient -L //192.168.50.2 -A /run/alex.auth -g"
        )
        assert "Disk|alex|" in shares
        assert "Disk|andreea|" in shares
        assert "Disk|media|" in shares
        for forbidden in ["homes", "apps", "root", "shared"]:
            assert f"Disk|{forbidden}|" not in shares
        client.succeed(
            "rm -f /tmp/home-leak; smbclient //192.168.50.2/homes -A /run/alex.auth -c 'get not-exported.txt /tmp/home-leak' >/dev/null 2>&1 || true; test ! -e /tmp/home-leak"
        )
        listing = client.succeed(
            "smbclient //192.168.50.2/alex -A /run/alex.auth -c 'recurse;ls'"
        )
        assert "private.txt" in listing
        assert "not-exported.txt" not in listing

    with subtest("private-share cross-owner isolation"):
        client.succeed(
            "smbclient //192.168.50.2/alex -A /run/alex.auth -c 'get private.txt /tmp/alex-private.txt'"
        )
        client.fail(
            "smbclient //192.168.50.2/andreea -A /run/alex.auth -c ls"
        )
        client.succeed(
            "smbclient //192.168.50.2/andreea -A /run/andreea.auth -c 'get private.txt /tmp/andreea-private.txt'"
        )
        client.fail(
            "smbclient //192.168.50.2/alex -A /run/andreea.auth -c ls"
        )

    with subtest("media read for both and Alex-only SMB writes"):
        client.succeed(
            "smbclient //192.168.50.2/media -A /run/alex.auth -c 'get shared.txt /tmp/media-alex.txt'"
        )
        client.succeed(
            "smbclient //192.168.50.2/media -A /run/andreea.auth -c 'get shared.txt /tmp/media-andreea.txt'"
        )
        client.fail(
            "smbclient //192.168.50.2/media -A /run/andreea.auth -c 'put /tmp/andreea-upload.txt andreea-upload.txt'"
        )
        client.succeed(
            "smbclient //192.168.50.2/media -A /run/alex.auth -c 'put /tmp/alex-upload.txt alex-upload.txt'"
        )
        server.succeed("grep -F 'alex upload' /srv/media/alex-upload.txt")
        server.fail("test -e /srv/media/andreea-upload.txt")
        server.succeed("test \"$(stat -c '%U:%G' /srv/media/alex-upload.txt)\" = alex:media")
        server.fail("su -s /bin/sh andreea -c 'touch /srv/media/direct-write-test'")
        server.fail("su - andreea -c true")
  '';
}
