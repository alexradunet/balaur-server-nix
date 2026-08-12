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
      # Exercise the secure loopback default rather than overriding it.
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
    grep --fixed-strings 'serviceUrl(8123)' index.html
    grep --fixed-strings 'serviceUrl(5230)' index.html
    grep --fixed-strings 'serviceUrl(8096)' index.html
    grep --fixed-strings 'serviceUrl(9696)' index.html
    grep --fixed-strings 'serviceUrl(8082)' index.html
    grep --fixed-strings 'serviceUrl(8084)' index.html
    ! grep --fixed-strings 'serviceUrl(8989)' index.html
    ! grep --fixed-strings 'serviceUrl(7878)' index.html
    ! grep --fixed-strings 'serviceUrl(8383)' index.html
    grep --fixed-strings 'serviceUrl(8083)' index.html
    ! grep --fixed-strings 'id="desktop"' index.html
    ! grep --fixed-strings 'id="herdr"' index.html
    ! grep --fixed-strings 'serviceUrl(6080' index.html
    ! grep --fixed-strings 'serviceUrl(7681' index.html
    grep --fixed-strings 'serviceUrl(8081, "/v1/models")' index.html
    grep --fixed-strings 'Prowlarr' index.html
    ! grep --fixed-strings 'Sonarr' index.html
    ! grep --fixed-strings 'Radarr' index.html
    grep --fixed-strings 'Manual media search' index.html
    grep --fixed-strings 'FastFlowLM' index.html
    grep --fixed-strings 'Balaur AI' index.html
    grep --fixed-strings 'Memos' index.html
    grep --fixed-strings 'Trilium' index.html
    grep --fixed-strings 'Structured notes' index.html
    ! grep --fixed-strings 'Nextcloud' index.html
    grep --fixed-strings '<h3 id="home-services">Home</h3>' index.html
    grep --fixed-strings '<h3 id="media-services">Media</h3>' index.html
    grep --fixed-strings '<h3 id="file-services">Downloads &amp; Files</h3>' index.html
    grep --fixed-strings '<h3 id="tool-services">Tools &amp; Compute</h3>' index.html
    test "$(grep --only-matching 'class="service-icon"' index.html | wc --lines)" = 8
    grep --fixed-strings '<section class="disks" id="disks"></section>' index.html
    grep --fixed-strings 'data.disks.map' index.html

      curl --silent --fail --output status.json http://127.0.0.1:18080/api/status
      jq --exit-status '
        .host == "balaur"
        and (.timestamp | type == "string")
        and (.uptime | type == "number")
        and (.memory.used | type == "number")
        and (.memory.total > 0)
        and (.disks | length == 5)
        and ([.disks[].id] == ["os", "app-data", "personal", "media-ssd0", "media-ssd1"])
        and (.disks[0].mounted == true)
        and (.disks[0].total > 0)
        and ([.disks[].mounted] | all(type == "boolean"))
        and (.services | length == 8)
        and ([.services[].id] == ["home-assistant", "memos", "jellyfin", "prowlarr", "qbittorrent", "trilium", "open-webui", "fastflowlm"])
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
