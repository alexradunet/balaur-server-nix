{ config, pkgs }:

let
  inherit (pkgs) lib;
  serviceNames = builtins.attrNames config.systemd.services;
  forbiddenServices = [
    "balaur-dashboard"
    "home-assistant"
    "jellyfin"
    "prowlarr"
    "prowlarr-qbittorrent-sync"
    "qbittorrent"
    "qbt-webui-proxy"
  ];
  assertions = [
    {
      assertion =
        !config.nixarr.enable
        && config.services.caddy.enable
        && config.balaur.ingress.reverseProxies == { };
      message = "Caddy ingress must be enabled without inventing shared application routes";
    }
    {
      assertion = lib.all (service: !builtins.elem service serviceNames) forbiddenServices;
      message = "dashboard and application shared-service units must not evaluate before issue 09";
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
    printf '%s\n' 'Shared-service baseline invariants passed.' > "$out/result"
  ''
