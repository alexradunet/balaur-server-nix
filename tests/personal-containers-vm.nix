{ sopsModule }:

{
  name = "balaur-personal-container-boundaries";

  nodes = {
    server =
      { lib, pkgs, ... }:
      let
        fakeLlama = pkgs.runCommand "fake-llama-cpp" { } ''
          mkdir -p "$out/bin"
          cat > "$out/bin/llama-server" <<'PY'
          #!${pkgs.python3}/bin/python3
          import json, sys
          from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
          args = sys.argv[1:]
          def value(flag): return args[args.index(flag) + 1]
          keys = set(open(value("--api-key-file"), encoding="utf-8").read().splitlines())
          class Handler(BaseHTTPRequestHandler):
              def log_message(self, *unused): pass
              def do_GET(self):
                  key = self.headers.get("Authorization", "").removeprefix("Bearer ")
                  body = json.dumps({"authorized": key in keys}).encode()
                  self.send_response(200 if key in keys else 401)
                  self.send_header("Content-Length", str(len(body)))
                  self.end_headers(); self.wfile.write(body)
          ThreadingHTTPServer((value("--host"), int(value("--port"))), Handler).serve_forever()
          PY
          chmod +x "$out/bin/llama-server"
        '';
        fakeApps =
          owner: address:
          pkgs.writeText "fake-personal-apps-${owner}.py" ''
            import http.server, pathlib, shutil, socketserver, threading, time
            owner = ${builtins.toJSON owner}
            address = ${builtins.toJSON address}
            class Handler(http.server.BaseHTTPRequestHandler):
                def log_message(self, *unused): pass
                def do_GET(self):
                    body = (owner + ":" + str(self.server.server_address[1])).encode()
                    self.send_response(200); self.send_header("Content-Length", str(len(body)))
                    self.end_headers(); self.wfile.write(body)
            for port in (80, 8080, 3000, 28981):
                server = socketserver.ThreadingTCPServer((address, port), Handler)
                threading.Thread(target=server.serve_forever, daemon=True).start()
            state = pathlib.Path("/srv/personal/paperless/consumed")
            state.mkdir(parents=True, exist_ok=True)
            consume = pathlib.Path("/srv/paperless/consume")
            while True:
                for source in consume.glob("*"):
                    if source.is_file():
                        shutil.copy2(source, state / source.name)
                        source.unlink()
                time.sleep(.2)
          '';
        ownerReadiness =
          owner:
          let
            root = "/run/balaur-secrets/owners/${owner}/personal";
          in
          {
            ready = true;
            importerReady = true;
            openWebuiAdminEmail = "${owner}@home.arpa";
            files = {
              paperlessAdminPassword = "${root}/paperless-admin-password";
              fireflyAppKey = "${root}/firefly-app-key";
              fireflyCronToken = "${root}/firefly-cron-token";
              openWebuiSecretKey = "${root}/open-webui-secret-key";
              openWebuiAdminPassword = "${root}/open-webui-admin-password";
              importerAccessToken = "${root}/importer-access-token";
              importerProxyPassword = "${root}/importer-proxy-password";
            };
          };
        testContainer = owner: address: {
          services = {
            postgresql.ensureDatabases = [ "owner-proof-${owner}" ];
            redis.servers.paperless.enable = lib.mkForce false;
            trilium-server.enable = lib.mkForce false;
            paperless.enable = lib.mkForce false;
            firefly-iii.enable = lib.mkForce false;
            firefly-iii-data-importer.enable = lib.mkForce false;
            open-webui.enable = lib.mkForce false;
            nginx.enable = lib.mkForce false;
            phpfpm.pools = lib.mkForce { };
          };
          users = {
            groups = {
              postgres.gid = 71;
              paperless.gid = 315;
              nginx.gid = 60;
            };
            users = {
              postgres = {
                uid = 71;
                isSystemUser = true;
                group = "postgres";
              };
              paperless = {
                uid = 315;
                isSystemUser = true;
                group = "paperless";
              };
              trilium = {
                uid = 900;
                isSystemUser = true;
                group = "trilium";
              };
              redis-paperless = {
                uid = 904;
                isSystemUser = true;
                group = "redis-paperless";
              };
              firefly-iii = {
                uid = 901;
                isSystemUser = true;
                group = "nginx";
              };
              firefly-iii-data-importer = {
                uid = 902;
                isSystemUser = true;
                group = "nginx";
              };
            };
          };
          environment.systemPackages = with pkgs; [
            curl
            gnugrep
            util-linux
          ];
          systemd.services.test-personal-apps = {
            wantedBy = [ "multi-user.target" ];
            requires = [
              "personal-stack-secrets.service"
              "personal-stack-version-gate.service"
            ];
            after = [
              "personal-stack-secrets.service"
              "personal-stack-version-gate.service"
            ];
            serviceConfig = {
              ExecStart = "${pkgs.python3}/bin/python3 ${fakeApps owner address}";
              Restart = "on-failure";
            };
          };
        };
      in
      {
        imports = [
          sopsModule
          ../modules/secrets.nix
          ../modules/networking.nix
          ../modules/llama.nix
          ../modules/personal-containers.nix
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

        users = {
          mutableUsers = false;
          allowNoPasswordLogin = true;
          users = {
            alex = {
              isNormalUser = true;
              group = "users";
            };
            andreea = {
              isNormalUser = true;
              group = "users";
            };
          };
        };

        balaur.personalContainers.owners = {
          alex.readiness = ownerReadiness "alex";
          andreea.readiness = ownerReadiness "andreea";
        };

        balaur.sharedServices.llama = {
          package = fakeLlama;
          readiness = {
            ready = true;
            modelPresetFile = "/srv/models/approved/router.ini";
            ownerApiKeyFiles = {
              alex = "/run/balaur-secrets/owners/alex/llama/api-key";
              andreea = "/run/balaur-secrets/owners/andreea/llama/api-key";
            };
            memoryHighBytes = 1073741824;
          };
        };

        containers = {
          alex-personal = {
            autoStart = lib.mkForce false;
            config = testContainer "alex" "10.231.12.2";
          };
          andreea-personal = {
            autoStart = lib.mkForce false;
            config = testContainer "andreea" "10.231.13.2";
          };
        };

        systemd.services = {
          llama-router.wantedBy = lib.mkForce [ ];
          personal-test-inputs = {
            before = [
              "llama-router.service"
              "container@alex-personal.service"
              "container@andreea-personal.service"
            ];
            requiredBy = [
              "llama-router.service"
              "container@alex-personal.service"
              "container@andreea-personal.service"
            ];
            after = [ "local-fs.target" ];
            unitConfig.ConditionPathIsMountPoint = [
              "/home/alex"
              "/home/andreea"
              "/srv/people/alex/apps"
              "/srv/people/andreea/apps"
              "/srv/models"
            ];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              UMask = "0077";
            };
            script = ''
              set -eu
              versions='trilium-server=0.102.2
              paperless-ngx=2.20.15
              firefly-iii=6.6.3
              firefly-iii-data-importer=2.3.4
              open-webui=0.11.0'
              for owner in alex andreea; do
                root="/run/balaur-secrets/owners/$owner"
                install -d -m 0700 "$root/personal" "$root/llama" "/home/$owner/files"
                printf '%s\n' "$versions" > "/srv/people/$owner/apps/approved-versions"
                ${pkgs.openssl}/bin/openssl rand -hex 24 > "$root/personal/paperless-admin-password"
                printf 'base64:' > "$root/personal/firefly-app-key"
                ${pkgs.openssl}/bin/openssl rand -base64 32 >> "$root/personal/firefly-app-key"
                ${pkgs.openssl}/bin/openssl rand -hex 16 > "$root/personal/firefly-cron-token"
                ${pkgs.openssl}/bin/openssl rand -hex 24 > "$root/personal/open-webui-secret-key"
                ${pkgs.openssl}/bin/openssl rand -hex 24 > "$root/personal/open-webui-admin-password"
                ${pkgs.openssl}/bin/openssl rand -hex 24 > "$root/personal/importer-access-token"
                printf 'TEST-ONLY-%s-importer-password\n' "$owner" > "$root/personal/importer-proxy-password"
                if test "$owner" = alex; then
                  printf '%s\n' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > "$root/llama/api-key"
                else
                  printf '%s\n' BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB > "$root/llama/api-key"
                fi
                chmod 0400 "$root"/personal/* "$root/llama/api-key"
                chown "$owner:users" "/home/$owner/files"
              done
              install -d -m 0755 /srv/models/approved
              : > /srv/models/approved/model.gguf
              cat > /srv/models/approved/router.ini <<'EOF'
              version = 1
              [approved]
              model = /srv/models/approved/model.gguf
              EOF
            '';
          };
        };

        environment.systemPackages = with pkgs; [
          acl
          curl
          iproute2
          netcat-openbsd
          util-linux
        ];
        virtualisation = {
          memorySize = 4096;
          cores = 4;
        };
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
    server.succeed("mkdir -p /home/alex /home/andreea /srv/people/alex/apps /srv/people/andreea/apps /srv/models")
    for path in ["/home/alex", "/home/andreea", "/srv/people/alex/apps", "/srv/people/andreea/apps", "/srv/models"]:
        server.succeed(f"mount -t tmpfs -o mode=0700 tmpfs {path}")
    server.succeed("chown alex:users /home/alex /srv/people/alex/apps; chown andreea:users /home/andreea /srv/people/andreea/apps; chmod 0700 /home/alex /home/andreea /srv/people/alex/apps /srv/people/andreea/apps")
    server.succeed("chmod 0755 /srv/models")
    server.succeed("systemctl start personal-test-inputs.service")
    server.succeed("systemctl restart caddy.service")
    server.succeed("chmod -R a+rX /srv/models")
    server.succeed("systemctl start llama-router.service")
    server.succeed("systemctl start container@alex-personal.service container@andreea-personal.service")
    server.wait_for_unit("llama-router.service")
    server.wait_for_unit("container@alex-personal.service")
    server.wait_for_unit("container@andreea-personal.service")
    server.wait_until_succeeds("systemctl -M alex-personal is-active --quiet test-personal-apps.service", timeout=30)
    server.wait_until_succeeds("systemctl -M andreea-personal is-active --quiet test-personal-apps.service", timeout=30)
    server.wait_until_succeeds("systemctl -M alex-personal is-active --quiet postgresql.service", timeout=30)
    server.wait_until_succeeds("systemctl -M andreea-personal is-active --quiet postgresql.service", timeout=30)

    with subtest("exact mounts, credentials, and no cross-owner trees"):
        for owner, other in [("alex", "andreea"), ("andreea", "alex")]:
            server.succeed(f"getfacl -cpn /srv/people/{owner}/apps | grep -Fx 'user:0:rwx'")
            server.succeed(f"getfacl -cpn /srv/people/{owner}/apps | grep -Fx 'user:71:--x'")
            server.succeed(f"getfacl -cpn /srv/people/{owner}/apps | grep -Fx 'group::---'")
            run = f"systemd-run -M {owner}-personal --pipe --wait --quiet /bin/sh -c"
            server.succeed(f"{run} 'mountpoint -q /srv/personal'")
            server.succeed(f"{run} 'mountpoint -q /srv/personal/open-webui/cache'")
            server.succeed(f"{run} 'mountpoint -q /srv/paperless/consume'")
            server.succeed(f"{run} 'findmnt -rn -o OPTIONS /run/owner-secrets | /run/current-system/sw/bin/grep -w ro'")
            server.succeed(f"systemd-run -M {owner}-personal --pipe --wait --quiet --uid=firefly-iii /bin/sh -c 'test -r /run/personal-stack/firefly-app-key'")
            server.succeed(f"systemd-run -M {owner}-personal --pipe --wait --quiet --uid=firefly-iii-data-importer /bin/sh -c 'test -r /run/personal-stack/importer-access-token'")
            server.succeed(f"systemd-run -M {owner}-personal --pipe --wait --quiet --uid=open-webui /bin/sh -c 'test -r /run/personal-stack/open-webui.env'")
            server.fail(f"systemd-run -M {owner}-personal --pipe --wait --quiet --uid=firefly-iii /bin/sh -c 'test -r /run/personal-stack/open-webui.env'")
            server.fail(f"{run} 'test -e /srv/people/{other}'")
            server.fail(f"{run} 'test -e /home/{other}'")
            server.fail(f"{run} 'test -e /run/owner-secrets/../{other}'")

    with subtest("Caddy is the only LAN app ingress"):
        server.succeed("systemd-run -M alex-personal --pipe --wait --quiet /bin/sh -c '/run/current-system/sw/bin/curl -fsS http://10.231.12.2:8080/ | /run/current-system/sw/bin/grep -Fx alex:8080'")
        server.succeed("systemd-run -M andreea-personal --pipe --wait --quiet /bin/sh -c '/run/current-system/sw/bin/curl -fsS http://10.231.13.2:8080/ | /run/current-system/sw/bin/grep -Fx andreea:8080'")
        server.wait_until_succeeds("curl --interface 10.231.12.1 -fsS http://10.231.12.2:8080/ | grep -Fx alex:8080", timeout=30)
        server.wait_until_succeeds("curl --interface 10.231.13.1 -fsS http://10.231.13.2:8080/ | grep -Fx andreea:8080", timeout=30)
        routes = [("notes.alex.home.arpa", "alex:8080"), ("paperless.alex.home.arpa", "alex:28981"), ("budget.andreea.home.arpa", "andreea:80"), ("chat.andreea.home.arpa", "andreea:3000")]
        for name, expected in routes:
            client.wait_until_succeeds(f"curl -kfsS --resolve {name}:443:192.168.50.2 https://{name}/ | grep -Fx {expected}", timeout=30)
        client.fail("curl -kfsS --resolve importer.alex.home.arpa:443:192.168.50.2 https://importer.alex.home.arpa/")
        client.wait_until_succeeds("curl -kfsS -u alex:TEST-ONLY-alex-importer-password --resolve importer.alex.home.arpa:443:192.168.50.2 https://importer.alex.home.arpa/ | grep -Fx alex:80", timeout=30)
        for port in [80, 3000, 8080, 28981]:
            client.fail(f"nc -z -w 1 10.231.12.2 {port}")
            client.fail(f"nc -z -w 1 10.231.13.2 {port}")

    with subtest("owner consume and database-like state remain separate"):
        server.succeed("printf 'alex document' > /home/alex/files/paperless-consume/alex.txt")
        server.wait_until_succeeds("grep -F 'alex document' /srv/people/alex/apps/paperless/consumed/alex.txt")
        server.fail("test -e /srv/people/andreea/apps/paperless/consumed/alex.txt")
        for owner, other in [("alex", "andreea"), ("andreea", "alex")]:
            psql = f"systemd-run -M {owner}-personal --pipe --wait --quiet --uid=postgres /run/current-system/sw/bin/psql -At postgres -c"
            own_query = f"SELECT datname FROM pg_database WHERE datname = 'owner-proof-{owner}'"
            other_query = f"SELECT datname FROM pg_database WHERE datname = 'owner-proof-{other}'"
            server.succeed(f'{psql} "{own_query}" | grep -Fx owner-proof-{owner}')
            assert server.succeed(f'{psql} "{other_query}"').strip() == ""
            server.fail(f"systemd-run -M {owner}-personal --pipe --wait --quiet /bin/sh -c 'test -e /srv/people/{other}/apps/postgresql'")

    with subtest("llama forwarding and key mounts are owner isolated"):
        alex_run = "systemd-run -M alex-personal --pipe --wait --quiet /bin/sh -c"
        andreea_run = "systemd-run -M andreea-personal --pipe --wait --quiet /bin/sh -c"
        server.succeed(f"{alex_run} \"/run/current-system/sw/bin/curl -fsS -H 'Authorization: Bearer AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' http://10.231.12.1:8081/ | /run/current-system/sw/bin/grep -F true\"")
        server.succeed(f"{andreea_run} \"/run/current-system/sw/bin/curl -fsS -H 'Authorization: Bearer BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' http://10.231.13.1:8081/ | /run/current-system/sw/bin/grep -F true\"")
        server.fail(f"{alex_run} 'test -e /run/owner-secrets/llama/andreea-api-key'")
        server.fail(f"{andreea_run} 'test -e /run/owner-secrets/llama/alex-api-key'")
        server.fail(f"{alex_run} \"/run/current-system/sw/bin/curl -m 2 -fsS -H 'Authorization: Bearer AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' http://10.231.13.1:8081/\"")
        server.fail(f"{andreea_run} \"/run/current-system/sw/bin/curl -m 2 -fsS -H 'Authorization: Bearer BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' http://10.231.12.1:8081/\"")
        client.fail("nc -z -w 1 192.168.50.2 8081")

    with subtest("equal soft resource controls"):
        for owner in ["alex", "andreea"]:
            unit = f"container@{owner}-personal.service"
            server.succeed(f"test $(systemctl show -P CPUWeight {unit}) = 100")
            server.succeed(f"test $(systemctl show -P IOWeight {unit}) = 100")
            server.succeed(f"test $(systemctl show -P ManagedOOMMemoryPressure {unit}) = kill")

    with subtest("symlinked consume path is rejected before writes"):
        server.succeed("systemctl stop container@alex-personal.service")
        server.succeed("rm -rf /home/alex/files/paperless-consume; install -d -m 0755 /tmp/consume-fallback; ln -s /tmp/consume-fallback /home/alex/files/paperless-consume")
        server.execute("systemctl start container@alex-personal.service")
        server.fail("systemctl is-active --quiet container@alex-personal.service")
        server.succeed("test $(stat -c '%a:%U:%G' /tmp/consume-fallback) = 755:root:root")
        server.succeed("rm /home/alex/files/paperless-consume; systemctl reset-failed container@alex-personal.service; systemctl start container@alex-personal.service")
        server.wait_for_unit("container@alex-personal.service")

    with subtest("missing owner app mount prevents fallback writes"):
        server.succeed("systemctl stop container@alex-personal.service")
        server.succeed("umount /srv/people/alex/apps")
        server.execute("systemctl start container@alex-personal.service")
        server.fail("systemctl is-active --quiet container@alex-personal.service")
        server.fail("test -e /srv/people/alex/apps/postgresql/17/PG_VERSION")
  '';
}
