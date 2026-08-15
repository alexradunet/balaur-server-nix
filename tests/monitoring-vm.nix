{
  name = "balaur-monitoring-behavior";

  nodes = {
    local =
      { lib, pkgs, ... }:
      {
        imports = [ ../modules/monitoring.nix ];
        options.balaur.storage = {
          ownerWarningBytes = lib.mkOption { type = lib.types.ints.positive; };
          protectedLeafDatasets = lib.mkOption { type = lib.types.listOf lib.types.str; };
          disposableDatasets = lib.mkOption { type = lib.types.listOf lib.types.str; };
        };
        config = {
          balaur.storage = {
            ownerWarningBytes = 180000000000;
            protectedLeafDatasets = [ "tank/protected" ];
            disposableDatasets = [ "tank/protected/disposable" ];
          };
          networking.hostId = "87654321";
          boot.zfs.forceImportRoot = false;
          boot.swraid.enable = true;
          services.openssh.enable = true;
          environment.systemPackages = [ pkgs.jq ];
          systemd.timers = {
            balaur-snapshot-daily.wantedBy = lib.mkForce [ ];
            balaur-snapshot-weekly.wantedBy = lib.mkForce [ ];
            balaur-md-check.wantedBy = lib.mkForce [ ];
            balaur-monitoring-check.wantedBy = lib.mkForce [ ];
          };
          virtualisation.memorySize = 1024;
        };
      };

    server =
      { lib, pkgs, ... }:
      {
        imports = [ ../modules/monitoring.nix ];

        options.balaur.storage = {
          ownerWarningBytes = lib.mkOption { type = lib.types.ints.positive; };
          protectedLeafDatasets = lib.mkOption { type = lib.types.listOf lib.types.str; };
          disposableDatasets = lib.mkOption { type = lib.types.listOf lib.types.str; };
        };

        config = {
          balaur.storage = {
            ownerWarningBytes = 180000000000;
            protectedLeafDatasets = [
              "tank/protected-a"
              "tank/protected-b"
            ];
            # This deliberately nests disposable state below a protected leaf.
            # Only genuinely non-recursive snapshots can pass the VM behavior.
            disposableDatasets = [ "tank/protected-a/disposable" ];
          };
          balaur.monitoring.readiness = {
            email = {
              ready = true;
              adapter = "/var/lib/balaur-monitoring-test/sendmail";
              sender = "monitor@example.invalid";
              recipient = "owner@example.invalid";
            };
            backup = {
              ready = true;
              stampFiles = {
                alex = "/var/lib/balaur-monitoring-test/alex-backup-stamp";
                andreea = "/var/lib/balaur-monitoring-test/andreea-backup-stamp";
              };
              capacityFiles = {
                alex = "/var/lib/balaur-monitoring-test/alex-backup-capacity";
                andreea = "/var/lib/balaur-monitoring-test/andreea-backup-capacity";
              };
              maxAgeSeconds = 3600;
            };
            thermal = {
              ready = true;
              sensorFiles = [ "/var/lib/balaur-monitoring-test/temperature" ];
              criticalMilliCelsius = 90000;
            };
          };

          networking.hostId = "12345678";
          boot.supportedFilesystems = [ "zfs" ];
          boot.zfs.forceImportRoot = false;
          boot.swraid.enable = true;

          environment.systemPackages = with pkgs; [
            jq
            zfs
          ];
          virtualisation = {
            emptyDiskImages = [ 2048 ];
            memorySize = 2048;
            cores = 2;
          };

          # Every timer is exercised explicitly; none may race test setup.
          systemd.timers = {
            balaur-snapshot-daily.wantedBy = lib.mkForce [ ];
            balaur-snapshot-weekly.wantedBy = lib.mkForce [ ];
            balaur-md-check.wantedBy = lib.mkForce [ ];
            balaur-monitoring-check.wantedBy = lib.mkForce [ ];
            balaur-monitoring-delivery.wantedBy = lib.mkForce [ ];
            balaur-monitoring-monthly-test.wantedBy = lib.mkForce [ ];
            zfs-scrub.wantedBy = lib.mkForce [ ];
          };
        };
      };
  };

  testScript =
    { nodes, ... }:
    let
      command = nodes.server.balaur.monitoring.command;
      localCommand = nodes.local.balaur.monitoring.command;
    in
    ''
      import json
      import shlex

      start_all()
      server.wait_for_unit("multi-user.target")
      local.wait_for_unit("multi-user.target")

      with subtest("production collection runs real host commands through the systemd interface"):
          local.succeed("systemctl start balaur-monitoring-check.service")
          local.succeed("test $(systemctl show -P Result balaur-monitoring-check.service) = success")
          local.succeed("journalctl -u balaur-monitoring-check.service --no-pager | grep -F '\"classes\"'")

      with subtest("initrd md events replay when mdadm reports a numbered device"):
          local.succeed("printf 'NewArray\\t/dev/md127\\n' > /run/balaur-md-events")
          local.succeed("chmod 0600 /run/balaur-md-events")
          local.succeed("systemctl restart balaur-md-early-events.service")
          local.succeed("test $(systemctl show -P Result balaur-md-early-events.service) = success")
          local.fail("test -e /run/balaur-md-events")

      with subtest("unexpectedly inactive administrative SSH alerts through real collection"):
          local.succeed("systemctl stop sshd.service")
          local.succeed("test $(systemctl show -P ActiveState sshd.service) = inactive")
          local.succeed("rm -f /var/lib/balaur-monitoring/alerts/* /var/lib/balaur-monitoring/active/*")
          local.succeed("${localCommand} check")
          local.succeed("jq -e 'select(.kind == \"required-unit-failed\" and .identity == \"sshd.service\")' /var/lib/balaur-monitoring/alerts/*.json >/dev/null")

      with subtest("durable local alerts work while email is not ready"):
          local.succeed("install -d -m 0700 /var/lib/balaur-monitoring-test")
          local_only = {
              "zfsHealthy": False,
              "zfsScrubHealthy": True,
              "mdHealthy": True,
              "mdScrubHealthy": True,
              "smartHealthy": True,
              "poolFull": False,
              "ownerUsageBytes": {"alex": 0, "andreea": 0},
              "failedUnits": [],
              "newOom": False,
              "swapUsedBytes": 0,
              "backupStale": {"alex": False, "andreea": False},
              "backupCapacityHigh": {"alex": False, "andreea": False},
              "thermalCritical": False,
              "thermalThrottling": False,
              "collectionErrors": [],
          }
          local.succeed("printf %s " + shlex.quote(json.dumps(local_only)) + " > /var/lib/balaur-monitoring-test/input.json")
          local.succeed("${localCommand} check --input /var/lib/balaur-monitoring-test/input.json")
          local.succeed("/etc/balaur-md-event Fail /dev/md/root")
          local.succeed("grep -F '\"kind\": \"zfs-degraded\"' /var/lib/balaur-monitoring/alerts/*.json")
          local.succeed("grep -F '\"summary\": \"md root event\"' /var/lib/balaur-monitoring/alerts/*.json")
          local.fail("test -e /var/lib/balaur-monitoring/outbox")

      server.succeed("install -d -m 0700 /var/lib/balaur-monitoring-test")
      server.succeed("printf '#!/bin/sh\\nset -eu\\nif test -e /var/lib/balaur-monitoring-test/fail; then exit 75; fi\\ncat >> /var/lib/balaur-monitoring/sent-mail.log\\n' > /var/lib/balaur-monitoring-test/sendmail")
      server.succeed("chmod 0700 /var/lib/balaur-monitoring-test/sendmail")
      server.succeed("touch /var/lib/balaur-monitoring-test/alex-backup-stamp /var/lib/balaur-monitoring-test/andreea-backup-stamp")
      server.succeed("printf '0\\n' > /var/lib/balaur-monitoring-test/alex-backup-capacity; printf '0\\n' > /var/lib/balaur-monitoring-test/andreea-backup-capacity")
      server.succeed("printf '42000\\n' > /var/lib/balaur-monitoring-test/temperature")

      with subtest("exact snapshots retain only module-owned names and exclude a disposable descendant"):
          server.succeed("zpool create -f tank /dev/vdb")
          server.succeed("zfs create tank/protected-a")
          server.succeed("zfs create tank/protected-a/disposable")
          server.succeed("zfs create tank/protected-b")
          for dataset in ["tank/protected-a", "tank/protected-b"]:
              for index in range(1, 10):
                  server.succeed(f"zfs snapshot {dataset}@balaur-monitoring-daily-202601{index:02d}T010000Z")
              for index in range(1, 7):
                  server.succeed(f"zfs snapshot {dataset}@balaur-monitoring-weekly-202602{index:02d}T010000Z")
          server.succeed("zfs snapshot tank/protected-a@owner-kept")
          server.succeed("${command} snapshot daily")
          server.succeed("${command} snapshot weekly")
          for dataset in ["tank/protected-a", "tank/protected-b"]:
              server.succeed(f"test $(zfs list -H -t snapshot -o name -d 1 {dataset} | grep -c '^{dataset}@balaur-monitoring-daily-') = 7")
              server.succeed(f"test $(zfs list -H -t snapshot -o name -d 1 {dataset} | grep -c '^{dataset}@balaur-monitoring-weekly-') = 4")
          server.succeed("test $(zfs list -H -t snapshot -o name -d 1 tank/protected-a | grep '^tank/protected-a@balaur-monitoring-daily-' | sort | tail -1 | cut -d@ -f2) = $(zfs list -H -t snapshot -o name -d 1 tank/protected-b | grep '^tank/protected-b@balaur-monitoring-daily-' | sort | tail -1 | cut -d@ -f2)")
          server.succeed("zfs list -H -t snapshot -o name tank/protected-a@owner-kept")
          assert server.succeed("zfs list -H -r -t snapshot -o name tank/protected-a/disposable").strip() == ""

      degraded = {
          "zfsHealthy": False,
          "zfsScrubHealthy": False,
          "mdHealthy": False,
          "mdScrubHealthy": False,
          "smartHealthy": False,
          "poolFull": True,
          "ownerUsageBytes": {"alex": 180000000000, "andreea": 0},
          "failedUnits": ["balaur-snapshot-daily.service"],
          "newOom": True,
          "swapUsedBytes": 1,
          "backupStale": {"alex": True, "andreea": False},
          "backupCapacityHigh": {"alex": True, "andreea": False},
          "thermalCritical": True,
          "thermalThrottling": True,
          "collectionErrors": [],
      }
      healthy = {
          "zfsHealthy": True,
          "zfsScrubHealthy": True,
          "mdHealthy": True,
          "mdScrubHealthy": True,
          "smartHealthy": True,
          "poolFull": False,
          "ownerUsageBytes": {"alex": 0, "andreea": 0},
          "failedUnits": [],
          "newOom": False,
          "swapUsedBytes": 0,
          "backupStale": {"alex": False, "andreea": False},
          "backupCapacityHigh": {"alex": False, "andreea": False},
          "thermalCritical": False,
          "thermalThrottling": False,
          "collectionErrors": [],
      }

      def write_input(name, value):
          path = "/var/lib/balaur-monitoring-test/" + name + ".json"
          server.succeed("printf %s " + shlex.quote(json.dumps(value)) + " > " + path)
          return path

      with subtest("normalized input classifies every alert without duplicate storms"):
          degraded_path = write_input("degraded", degraded)
          output = json.loads(server.succeed("${command} check --input " + degraded_path))
          assert output["active"] == 14
          assert output["classes"] == [
              "backup-capacity",
              "backup-stale",
              "md-degraded",
              "md-scrub",
              "oom",
              "owner-usage",
              "pool-full",
              "required-unit-failed",
              "smart-health",
              "swap",
              "thermal-critical",
              "thermal-throttling",
              "zfs-degraded",
              "zfs-scrub",
          ]
          assert int(server.succeed("find /var/lib/balaur-monitoring/alerts -type f | wc -l")) == 14
          server.succeed("${command} check --input " + degraded_path)
          assert int(server.succeed("find /var/lib/balaur-monitoring/alerts -type f | wc -l")) == 14
          unknown = dict(healthy)
          unknown["collectionErrors"] = ["zfs"]
          unknown_path = write_input("unknown-zfs", unknown)
          unknown_output = json.loads(server.succeed("${command} check --input " + unknown_path))
          assert unknown_output == {"active": 4, "classes": ["collection-failure", "pool-full", "zfs-degraded", "zfs-scrub"]}
          assert int(server.succeed("find /var/lib/balaur-monitoring/alerts -type f | wc -l")) == 15
          healthy_path = write_input("healthy", healthy)
          server.succeed("${command} check --input " + healthy_path)
          assert int(server.succeed("find /var/lib/balaur-monitoring/active -type f | wc -l")) == 0

      with subtest("stranded temporary writes cannot wedge alert delivery"):
          server.succeed("test -d /var/lib/balaur-monitoring/tmp")
          server.succeed("install -m 0600 /dev/null /var/lib/balaur-monitoring/tmp/.new-stranded")
          server.succeed("${command} check --input " + healthy_path)

      with subtest("successful sendmail delivery and monthly end-to-end test are archived"):
          server.succeed("${command} deliver")
          assert int(server.succeed("find /var/lib/balaur-monitoring/outbox -type f | wc -l")) == 0
          assert int(server.succeed("find /var/lib/balaur-monitoring/sent -type f | wc -l")) == 15
          server.succeed("${command} monthly-test")
          assert int(server.succeed("find /var/lib/balaur-monitoring/sent -type f | wc -l")) == 16
          server.succeed("grep -F 'Subject: Balaur alert: Monthly end-to-end test' /var/lib/balaur-monitoring/sent-mail.log")
          server.succeed("grep -F 'To: owner@example.invalid' /var/lib/balaur-monitoring/sent-mail.log")

      with subtest("failed adapter retains outbox and is visible as a failed unit"):
          server.succeed("touch /var/lib/balaur-monitoring-test/fail")
          failed_delivery = dict(healthy)
          failed_delivery["zfsHealthy"] = False
          failure_path = write_input("delivery-failure", failed_delivery)
          server.succeed("${command} check --input " + failure_path)
          queued_before = int(server.succeed("find /var/lib/balaur-monitoring/outbox -type f | wc -l"))
          assert queued_before == 1
          server.fail("systemctl start balaur-monitoring-delivery.service")
          server.succeed("systemctl is-failed --quiet balaur-monitoring-delivery.service")
          assert int(server.succeed("find /var/lib/balaur-monitoring/outbox -type f | wc -l")) == queued_before
          server.succeed("journalctl -u balaur-monitoring-delivery.service --no-pager | grep -F 'retained after delivery failure'")
          server.succeed("jq -e 'select(.kind == \"zfs-degraded\")' /var/lib/balaur-monitoring/alerts/*.json >/dev/null")
    '';
}
