{ sopsModule }:

{
  name = "balaur-llama-service-interface";

  nodes = {
    server =
      { lib, pkgs, ... }:
      let
        fakeServer = pkgs.writeText "fake-llama-server.py" ''
          import json
          import sys
          import time
          from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

          args = sys.argv[1:]
          def value(flag):
              return args[args.index(flag) + 1]

          port = int(value("--port"))
          idle_enabled = int(value("--sleep-idle-seconds")) > 0
          keys = set(open(value("--api-key-file"), encoding="utf-8").read().splitlines())
          state = {"value": "unloaded", "last": time.monotonic()}

          class Handler(BaseHTTPRequestHandler):
              def log_message(self, *unused):
                  pass

              def authorized(self):
                  return self.headers.get("Authorization", "").removeprefix("Bearer ") in keys

              def reply(self, code, body):
                  data = json.dumps(body).encode()
                  self.send_response(code)
                  self.send_header("Content-Type", "application/json")
                  self.send_header("Content-Length", str(len(data)))
                  self.end_headers()
                  self.wfile.write(data)

              def do_GET(self):
                  if self.path in ("/health", "/v1/health"):
                      self.reply(200, {"status": "ok"})
                      return
                  if not self.authorized():
                      self.reply(401, {"error": "unauthorized"})
                      return
                  if idle_enabled and state["value"] == "loaded" and time.monotonic() - state["last"] > 1:
                      # Disposable interface test: compress 1800 seconds to one second.
                      state["value"] = "sleeping"
                  if self.path == "/models":
                      self.reply(200, {"data": [{"id": "approved", "status": {"value": state["value"]}}]})
                  else:
                      self.reply(404, {})

              def do_POST(self):
                  if not self.authorized():
                      self.reply(401, {"error": "unauthorized"})
                      return
                  length = int(self.headers.get("Content-Length", "0"))
                  body = json.loads(self.rfile.read(length) or b"{}")
                  if self.path == "/models/unload":
                      state["value"] = "unloaded"
                  elif self.path in ("/models/load", "/v1/chat/completions"):
                      state["value"] = "loaded"
                      state["last"] = time.monotonic()
                  self.reply(200, {"success": True, "model": body.get("model")})

          ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
        '';
        fakePackage = pkgs.runCommand "fake-llama-cpp" { } ''
          mkdir -p "$out/bin"
          cat > "$out/bin/llama-server" <<'SH'
          #!${pkgs.runtimeShell}
          printf '%s\n' "$@" > /run/llama-router/fake-args
          exec ${pkgs.python3}/bin/python3 ${fakeServer} "$@"
          SH
          chmod +x "$out/bin/llama-server"
        '';
      in
      {
        imports = [
          sopsModule
          ../modules/secrets.nix
          ../modules/networking.nix
          ../modules/llama.nix
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
          };
        };

        systemd.services = {
          llama-test-inputs = {
            before = [ "llama-router.service" ];
            requiredBy = [ "llama-router.service" ];
            after = [ "systemd-tmpfiles-setup.service" ];
            unitConfig.ConditionPathIsMountPoint = [ "/srv/models" ];
            serviceConfig.Type = "oneshot";
            script = ''
              install -d -m 0755 /srv/models/approved
              : > /srv/models/approved/model.gguf
              cat > /srv/models/approved/router.ini <<'EOF'
              version = 1
              [approved]
              model = /srv/models/approved/model.gguf
              EOF
              install -d -m 0700 /run/balaur-secrets/owners/alex/llama
              install -d -m 0700 /run/balaur-secrets/owners/andreea/llama
              printf '%s\n' AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA > /run/balaur-secrets/owners/alex/llama/api-key
              printf '%s\n' BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB > /run/balaur-secrets/owners/andreea/llama/api-key
              chmod 0600 /run/balaur-secrets/owners/*/llama/api-key
            '';
          };
          llama-router = {
            # The test mounts /srv/models manually so disappearance cannot be
            # hidden by an always-available tmpfs mount unit.
            wantedBy = lib.mkForce [ ];
            requires = lib.mkAfter [ "llama-test-inputs.service" ];
            after = lib.mkAfter [ "llama-test-inputs.service" ];
          };
        };

        balaur.sharedServices.llama = {
          package = fakePackage;
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

        environment.systemPackages = with pkgs; [
          curl
          iproute2
          netcat-openbsd
          util-linux
        ];
        virtualisation.memorySize = 1536;
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
        environment.systemPackages = [ pkgs.netcat-openbsd ];
      };
  };

  testScript = ''
    server.start()
    client.start()
    server.succeed("mkdir -p /srv/models; mount -t tmpfs -o mode=0755,size=32M tmpfs /srv/models")
    server.succeed("systemctl start llama-router.service")
    server.wait_for_unit("llama-router.service")

    with subtest("exact private router interface and two owner keys"):
        server.wait_until_succeeds("ss -lntH | grep -F '127.0.0.1:8081'")
        server.fail("ss -lntH | grep -F '192.168.50.2:8081'")
        client.fail("nc -z -w 1 192.168.50.2 8081")
        server.fail("curl --fail --silent http://127.0.0.1:8081/models")
        for key in ["AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"]:
            server.succeed(f"curl --fail --silent -H 'Authorization: Bearer {key}' http://127.0.0.1:8081/models")
        server.succeed("test $(wc -l < /run/llama-router/api-keys) = 2")

    with subtest("lazy startup and b9190 idle-sleep contract"):
        server.succeed("curl --silent -H 'Authorization: Bearer AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' http://127.0.0.1:8081/models | grep -F '\"value\": \"unloaded\"'")
        server.succeed("curl --fail --silent -H 'Authorization: Bearer AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' -H 'Content-Type: application/json' -d '{\"model\":\"approved\"}' http://127.0.0.1:8081/v1/chat/completions")
        server.succeed("curl --silent -H 'Authorization: Bearer AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' http://127.0.0.1:8081/models | grep -F '\"value\": \"loaded\"'")
        server.sleep(2)
        server.succeed("curl --silent -H 'Authorization: Bearer AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' http://127.0.0.1:8081/models | grep -F '\"value\": \"sleeping\"'")
        server.succeed("grep -Fx -- '--sleep-idle-seconds' /run/llama-router/fake-args")
        server.succeed("grep -Fx -- '1800' /run/llama-router/fake-args")

    with subtest("models mount disappearance fails closed"):
        server.succeed("systemctl stop llama-router.service llama-test-inputs.service")
        server.succeed("umount /srv/models")
        server.execute("systemctl start llama-router.service")
        server.fail("systemctl is-active --quiet llama-router.service")
        server.fail("test -e /srv/models/approved/router.ini")
  '';
}
