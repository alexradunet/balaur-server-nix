{ config, pkgs }:

let
  inherit (pkgs) lib;
  serviceNames = builtins.attrNames config.systemd.services;
  forbiddenServices = [
    "balaur-dashboard"
    "caddy"
    "home-assistant"
    "jellyfin"
    "prowlarr"
    "prowlarr-qbittorrent-sync"
    "qbittorrent"
    "qbt-webui-proxy"
  ];
  assertions = [
    {
      assertion = !config.nixarr.enable && !config.services.caddy.enable;
      message = "nixarr and Caddy must remain available but disabled until their target tickets";
    }
    {
      assertion = lib.all (service: !builtins.elem service serviceNames) forbiddenServices;
      message = "dashboard and legacy shared-service units must not evaluate in the baseline";
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
