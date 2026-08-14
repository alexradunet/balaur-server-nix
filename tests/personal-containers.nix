{ config, pkgs }:

let
  inherit (pkgs) lib;
  personalServiceFragments = [
    "firefly"
    "open-webui"
    "paperless"
    "trilium"
  ];
  personalServices = builtins.filter (
    service: lib.any (fragment: lib.hasInfix fragment service) personalServiceFragments
  ) (builtins.attrNames config.systemd.services);
  assertions = [
    {
      assertion = config.containers == { };
      message = "personal containers must not be invented before issue 12";
    }
    {
      assertion = personalServices == [ ];
      message = "host-level Trilium, Paperless, Firefly, and Open WebUI units must remain absent";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur personal-container invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-personal-containers-tests" { } ''
    mkdir -p "$out"
    printf '%s\n' 'Personal-container baseline invariants passed.' > "$out/result"
  ''
