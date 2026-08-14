{ config, pkgs }:

let
  inherit (pkgs) lib;
  assertions = [
    {
      assertion = !(config.fileSystems ? "/mnt/balaur-backup");
      message = "the legacy label-based USB backup mount must remain absent";
    }
    {
      assertion = !(config.systemd.services ? balaur-backup) && !(config.systemd.timers ? balaur-backup);
      message = "the obsolete monolithic daily backup service and timer must remain absent";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur backup invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-backup-tests" { } ''
    mkdir -p "$out"
    printf '%s\n' 'Backup baseline invariants passed.' > "$out/result"
  ''
