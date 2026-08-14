{ config, pkgs }:

let
  inherit (pkgs) lib;
  assertions = [
    {
      assertion =
        config.services.smartd.enable
        && config.services.smartd.autodetect
        && !config.services.smartd.notifications.mail.enable
        && !config.services.smartd.notifications.systembus-notify.enable
        && !config.services.smartd.notifications.x11.enable;
      message = "baseline NVMe SMART monitoring must remain enabled without unconfigured alerts";
    }
    {
      assertion =
        config.nix.gc.automatic
        && config.nix.gc.options == "--delete-older-than 30d"
        && config.nix.optimise.automatic
        && config.zramSwap.enable
        && config.zramSwap.memoryPercent == 25;
      message = "baseline store maintenance and compressed emergency swap must remain enabled";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur monitoring invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-monitoring-tests" { } ''
    mkdir -p "$out"
    printf '%s\n' 'Monitoring baseline invariants passed.' > "$out/result"
  ''
