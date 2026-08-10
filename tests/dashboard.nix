{ pkgs }:

pkgs.runCommand "balaur-dashboard-tests"
  {
    nativeBuildInputs = with pkgs; [
      curl
      jq
      nodejs
    ];
  }
  ''
      export DASHBOARD_HOST=127.0.0.1
      export DASHBOARD_PORT=18080

      node ${../dashboard}/server.mts >dashboard.log 2>&1 &
      server_pid=$!
      trap 'kill "$server_pid" 2>/dev/null || true' EXIT

      for attempt in $(seq 1 50); do
        if curl --silent --fail http://127.0.0.1:18080/ >/dev/null; then
          break
        fi
        sleep 0.1
      done

      curl --silent --fail --dump-header headers --output index.html http://127.0.0.1:18080/
      grep --ignore-case '^content-type: text/html; charset=utf-8' headers
      grep --ignore-case '^content-security-policy:' headers
      grep --ignore-case '^x-frame-options: DENY' headers
    grep --fixed-strings '<title>balaur</title>' index.html

      curl --silent --fail --output status.json http://127.0.0.1:18080/api/status
      jq --exit-status '
        .host == "balaur"
        and (.timestamp | type == "string")
        and (.uptime | type == "number")
        and (.memory.used | type == "number")
        and (.memory.total > 0)
        and (.disk.total > 0)
        and (.services | length == 5)
        and ([.services[].id] == ["headscale", "syncthing", "desktop", "herdr", "llama"])
        and ([.services[].online] | all(type == "boolean"))
      ' status.json

      sleep 0.1
      curl --silent --fail --output second-status.json http://127.0.0.1:18080/api/status
      jq --exit-status '.cpu | type == "number"' second-status.json

      test "$(curl --silent --output not-found --write-out '%{http_code}' http://127.0.0.1:18080/missing)" = 404
    grep --fixed-strings 'Not found' not-found

    kill "$server_pid"
    wait "$server_pid" || true
      trap - EXIT
      mkdir -p "$out"
      cp status.json "$out/status.json"
  ''
