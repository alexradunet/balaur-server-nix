{ config, pkgs }:

let
  inherit (pkgs) lib;
  monitoring = config.balaur.monitoring;
  expectedDatasets = config.balaur.storage.protectedLeafDatasets;
  assertions = [
    {
      assertion =
        monitoring.snapshots.datasets == expectedDatasets
        &&
          monitoring.snapshots.retention == {
            daily = 7;
            weekly = 4;
          };
      message = "monitoring must expose the exact protected-leaf snapshot allowlist and retention";
    }
    {
      assertion =
        !config.services.zfs.autoSnapshot.enable
        && config.services.zfs.autoScrub.enable
        && config.services.zfs.autoScrub.pools == [ "tank" ];
      message = "tank scrub must be enabled without broad zfs-auto-snapshot semantics";
    }
    {
      assertion =
        config.services.smartd.enable
        && config.services.smartd.autodetect
        && !config.services.smartd.notifications.mail.enable
        && !config.services.smartd.notifications.wall.enable
        && !config.services.smartd.notifications.systembus-notify.enable
        && !config.services.smartd.notifications.x11.enable;
      message = "SMART/NVMe policy must be local and provider-neutral";
    }
    {
      assertion =
        lib.hasInfix "PROGRAM /etc/balaur-md-event" config.boot.swraid.mdadmConf
        &&
          config.boot.initrd.extraFiles."/etc/balaur-md-event".source
          == config.environment.etc."balaur-md-event".source
        &&
          config.boot.initrd.systemd.contents."/etc/balaur-md-event".source
          == config.environment.etc."balaur-md-event".source
        && config.environment.etc."balaur-md-event".mode == "0755"
        && !(lib.hasInfix "/nix/store/" config.boot.swraid.mdadmConf)
        && !(lib.hasInfix "MAILADDR" config.boot.swraid.mdadmConf);
      message = "md events must use one initrd-safe local bridge instead of MAILADDR or an unavailable store path";
    }
    {
      assertion =
        config.systemd.timers.balaur-snapshot-daily.timerConfig.Persistent
        && config.systemd.timers.balaur-snapshot-weekly.timerConfig.Persistent
        && config.systemd.timers.balaur-md-check.timerConfig.Persistent
        && config.systemd.timers.balaur-monitoring-check.timerConfig.Persistent;
      message = "snapshot, md check, and health timers must catch up persistently";
    }
    {
      assertion =
        !monitoring.readiness.email.ready
        && monitoring.readiness.email.adapter == null
        && monitoring.readiness.email.sender == null
        && monitoring.readiness.email.recipient == null
        && !monitoring.readiness.backup.ready
        && monitoring.readiness.backup.stampFiles == { }
        && monitoring.readiness.backup.capacityFiles == { }
        && monitoring.readiness.backup.capacityWarningPercent == 85
        && monitoring.readiness.backup.maxAgeSeconds == null
        && !monitoring.readiness.thermal.ready
        && monitoring.readiness.thermal.sensorFiles == [ ]
        && monitoring.readiness.thermal.criticalMilliCelsius == null;
      message = "unknown email, backup-freshness, and numeric thermal inputs must fail closed";
    }
    {
      assertion =
        !(builtins.hasAttr "balaur-monitoring-monthly-test" config.systemd.timers)
        && lib.count (warning: lib.hasInfix "BLOCKER" warning) config.warnings >= 3;
      message = "default production must disable monthly mail and surface every human readiness blocker";
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
    {
      assertion = !(config.services ? prometheus) || !config.services.prometheus.enable;
      message = "Prometheus must remain disabled";
    }
    {
      assertion = !(config.services ? grafana) || !config.services.grafana.enable;
      message = "Grafana must remain disabled";
    }
    {
      assertion = !config.power.ups.enable;
      message = "NUT/UPS monitoring must remain disabled";
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
    printf '%s\n' 'All ${toString (builtins.length assertions)} monitoring invariants passed.' > "$out/result"
  ''
