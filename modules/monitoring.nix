{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.balaur.monitoring;
  storage = config.balaur.storage;
  stateDirectory = "balaur-monitoring";
  statePath = "/var/lib/${stateDirectory}";
  ownerDatasets = {
    alex = "tank/users/alex";
    andreea = "tank/users/andreea";
  };
  expectedOwners = builtins.attrNames ownerDatasets;
  llamaReady = lib.attrByPath [
    "balaur"
    "sharedServices"
    "llama"
    "readiness"
    "ready"
  ] false config;
  alexContainerReady = lib.attrByPath [
    "containers"
    "alex-personal"
    "autoStart"
  ] false config;
  andreeaContainerReady = lib.attrByPath [
    "containers"
    "andreea-personal"
    "autoStart"
  ] false config;
  requiredActiveUnits = [
    "mdmonitor.service"
    "smartd.service"
    "zfs-zed.service"
  ]
  ++ lib.optional config.services.openssh.enable "sshd.service"
  ++ lib.optional config.services.caddy.enable "caddy.service"
  ++ lib.optional config.services.coredns.enable "coredns.service"
  ++ lib.optional config.services.home-assistant.enable "home-assistant.service"
  ++ lib.optional config.services.jellyfin.enable "jellyfin.service"
  ++ lib.optional config.services.samba.enable "samba-smbd.service"
  ++ lib.optionals config.services.qbittorrent.enable [
    "qbittorrent.service"
    "qbt-webui-proxy.service"
  ]
  ++ lib.optional llamaReady "llama-router.service"
  ++ lib.optional alexContainerReady "container@alex-personal.service"
  ++ lib.optional andreeaContainerReady "container@andreea-personal.service"
  ++ lib.optional (llamaReady && alexContainerReady) "llama-forward-alex.socket"
  ++ lib.optional (llamaReady && andreeaContainerReady) "llama-forward-andreea.socket";
  requiredFailureOnlyUnits = [
    "zfs-scrub.service"
    "balaur-snapshot-daily.service"
    "balaur-snapshot-weekly.service"
    "balaur-md-check.service"
    "balaur-md-early-events.service"
  ];
  requiredUnits = requiredActiveUnits ++ requiredFailureOnlyUnits;
  absoluteCanonical =
    path:
    path != null
    && lib.hasPrefix "/" path
    && !(lib.hasInfix "//" path)
    && !(lib.hasInfix "/../" path)
    && !(lib.hasSuffix "/.." path)
    && !(lib.hasInfix "/./" path)
    && !(lib.hasSuffix "/." path);
  noHeaderInjection = value: value != null && builtins.match "[^\r\n]+" value != null;
  emailAddress =
    value:
    value != null
    && builtins.match "[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+" value != null
    && !(lib.hasPrefix "-" value);
  emailComplete =
    cfg.readiness.email.adapter != null
    && cfg.readiness.email.sender != null
    && cfg.readiness.email.recipient != null;
  backupComplete =
    builtins.attrNames cfg.readiness.backup.stampFiles == expectedOwners
    && builtins.attrNames cfg.readiness.backup.capacityFiles == expectedOwners
    && cfg.readiness.backup.maxAgeSeconds != null;
  thermalComplete =
    cfg.readiness.thermal.sensorFiles != [ ] && cfg.readiness.thermal.criticalMilliCelsius != null;

  mdEventBridge = pkgs.writeTextFile {
    name = "balaur-md-event";
    executable = true;
    text = ''
      #!/bin/sh
      set -eu
      case "$#" in
        2|3) ;;
        *) exit 1 ;;
      esac
      if test -x /run/current-system/sw/bin/balaur-monitor; then
        exec /run/current-system/sw/bin/balaur-monitor "$@"
      fi
      umask 077
      printf '%s\t%s\n' "$1" "$2" >> /run/balaur-md-events
    '';
  };

  runtimeConfig = pkgs.writeText "balaur-monitoring.json" (
    builtins.toJSON {
      inherit
        statePath
        ownerDatasets
        requiredUnits
        requiredActiveUnits
        ;
      snapshots = {
        datasets = cfg.snapshots.datasets;
        retention = cfg.snapshots.retention;
        namespace = "balaur-monitoring";
      };
      ownerWarningBytes = storage.ownerWarningBytes;
      backupCapacityWarningPercent = cfg.readiness.backup.capacityWarningPercent;
      readiness = {
        email = cfg.readiness.email;
        backup = cfg.readiness.backup;
        thermal = cfg.readiness.thermal;
      };
      commands = {
        zfs = lib.getExe' config.boot.zfs.package "zfs";
        zpool = lib.getExe' config.boot.zfs.package "zpool";
        mdadm = lib.getExe' pkgs.mdadm "mdadm";
        smartctl = lib.getExe' pkgs.smartmontools "smartctl";
        systemctl = lib.getExe' config.systemd.package "systemctl";
        journalctl = lib.getExe' config.systemd.package "journalctl";
      };
    }
  );

  monitoringProgram = pkgs.writeTextFile {
    name = "balaur-monitor";
    destination = "/bin/balaur-monitor";
    executable = true;
    text = ''
      #!${pkgs.python3}/bin/python3
      import argparse
      import contextlib
      import datetime
      import email.policy
      import email.utils
      import fcntl
      import hashlib
      import json
      import os
      import pathlib
      import re
      import stat
      import subprocess
      import sys
      import tempfile
      import time
      import uuid
      from email.message import EmailMessage

      CONFIG_PATH = ${builtins.toJSON (toString runtimeConfig)}
      with open(CONFIG_PATH, "r", encoding="utf-8") as handle:
          CONFIG = json.load(handle)
      STATE = pathlib.Path(CONFIG["statePath"])
      SAFE_NAME = re.compile(r"^[0-9a-f]{64}$")
      SAFE_ALERT_ID = re.compile(r"^[0-9]{8}T[0-9]{6}\.[0-9]{6}Z-[0-9a-f]{32}$")
      UNKNOWN_KINDS = {
          "zfs": {"zfs-degraded", "zfs-scrub", "pool-full"},
          "md": {"md-degraded", "md-scrub"},
          "smart": {"smart-health"},
          "owner": {"owner-usage"},
          "units": {"required-unit-failed"},
          "journal": {"oom", "thermal-critical", "thermal-throttling", "smart-health"},
          "swap": {"swap"},
          "backup": {"backup-stale", "backup-capacity"},
          "thermal": {"thermal-critical"},
      }

      def fail(message):
          print("balaur-monitor: " + message, file=sys.stderr)
          raise RuntimeError(message)

      def run(command, check=True, timeout=60):
          result = subprocess.run(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True, timeout=timeout, check=False)
          if check and result.returncode != 0:
              fail("command failed with status " + str(result.returncode) + ": " + pathlib.Path(command[0]).name)
          return result

      def check_runtime_path(raw_path, executable=False):
          if not isinstance(raw_path, str) or not raw_path.startswith("/") or os.path.normpath(raw_path) != raw_path:
              fail("configured runtime path is not absolute and canonical")
          current = pathlib.Path("/")
          parts = pathlib.PurePath(raw_path).parts[1:]
          for index, part in enumerate(parts):
              current = current / part
              try:
                  info = current.lstat()
              except FileNotFoundError:
                  fail("configured runtime path is missing: " + raw_path)
              if stat.S_ISLNK(info.st_mode):
                  fail("configured runtime path contains a symlink: " + raw_path)
              if info.st_uid != 0 or info.st_mode & 0o022:
                  fail("configured runtime path is not protected from non-root writes: " + raw_path)
              if index < len(parts) - 1 and not stat.S_ISDIR(info.st_mode):
                  fail("configured runtime path has a non-directory parent: " + raw_path)
          info = pathlib.Path(raw_path).stat()
          if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
              fail("configured runtime file must be regular, root-owned, and protected from non-root writes: " + raw_path)
          if executable and info.st_mode & 0o111 == 0:
              fail("configured adapter is not executable")
          return pathlib.Path(raw_path)

      def secure_state_dir(name=None):
          path = STATE if name is None else STATE / name
          if name is not None and ("/" in name or name in ("", ".", "..")):
              fail("invalid state directory name")
          try:
              info = path.lstat()
          except FileNotFoundError:
              path.mkdir(mode=0o700)
              info = path.lstat()
          if (not stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode)
                  or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o700):
              fail("monitoring state path is not a mode-0700 root-owned directory: " + str(path))
          return path

      @contextlib.contextmanager
      def state_lock():
          secure_state_dir()
          lock_path = STATE / "lock"
          descriptor = os.open(lock_path, os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
          try:
              info = os.fstat(descriptor)
              if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o077:
                  fail("monitoring state lock is unsafe")
              fcntl.flock(descriptor, fcntl.LOCK_EX)
              yield
          finally:
              os.close(descriptor)

      def atomic_write(directory, name, payload, mode=0o600):
          if "/" in name or name in ("", ".", ".."):
              fail("invalid state file name")
          secure_state_dir()
          directory = secure_state_dir(directory.name)
          # Keep incomplete writes out of directories consumed as queues or
          # marker sets. A crash can strand a file in tmp, but cannot wedge
          # later alert checks or deliveries.
          temporary_directory = secure_state_dir("tmp")
          fd, temporary = tempfile.mkstemp(prefix=".new-", dir=str(temporary_directory))
          try:
              os.fchmod(fd, mode)
              with os.fdopen(fd, "wb") as handle:
                  handle.write(payload)
                  handle.flush()
                  os.fsync(handle.fileno())
              os.replace(temporary, directory / name)
              directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
              try:
                  os.fsync(directory_fd)
              finally:
                  os.close(directory_fd)
          finally:
              try:
                  os.unlink(temporary)
              except FileNotFoundError:
                  pass

      def timestamp():
          return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

      def finding(kind, identity, summary, detail):
          return {"kind": kind, "identity": identity, "summary": summary, "detail": detail}

      def md_sysfs():
          block_name = pathlib.Path("/dev/md/root").resolve(strict=True).name
          root = pathlib.Path("/sys/class/block") / block_name / "md"
          if not root.is_dir():
              fail("md sysfs state is unavailable")
          return root

      def validate_normalized(data):
          expected = {
              "zfsHealthy", "zfsScrubHealthy", "mdHealthy", "mdScrubHealthy", "smartHealthy",
              "poolFull", "ownerUsageBytes", "failedUnits", "newOom", "swapUsedBytes",
              "backupStale", "backupCapacityHigh", "thermalCritical", "thermalThrottling",
              "collectionErrors"
          }
          if not isinstance(data, dict) or set(data) != expected:
              fail("normalized input must contain exactly the documented fields")
          for field in ("zfsHealthy", "zfsScrubHealthy", "mdHealthy", "mdScrubHealthy", "smartHealthy", "poolFull", "newOom", "thermalCritical", "thermalThrottling"):
              if type(data[field]) is not bool:
                  fail("normalized field is not boolean: " + field)
          owners = set(CONFIG["ownerDatasets"])
          if not isinstance(data["ownerUsageBytes"], dict) or set(data["ownerUsageBytes"]) != owners:
              fail("normalized owner usage must cover the configured owners exactly")
          if not isinstance(data["backupStale"], dict) or set(data["backupStale"]) != owners:
              fail("normalized backup freshness must cover the configured owners exactly")
          if not isinstance(data["backupCapacityHigh"], dict) or set(data["backupCapacityHigh"]) != owners:
              fail("normalized backup capacity must cover the configured owners exactly")
          for owner in owners:
              if type(data["ownerUsageBytes"][owner]) is not int or data["ownerUsageBytes"][owner] < 0:
                  fail("normalized owner usage must be a non-negative integer")
              if type(data["backupStale"][owner]) is not bool:
                  fail("normalized backup freshness must be boolean")
              if type(data["backupCapacityHigh"][owner]) is not bool:
                  fail("normalized backup capacity must be boolean")
          if type(data["swapUsedBytes"]) is not int or data["swapUsedBytes"] < 0:
              fail("normalized swap use must be a non-negative integer")
          if not isinstance(data["failedUnits"], list) or any(unit not in CONFIG["requiredUnits"] for unit in data["failedUnits"]):
              fail("normalized failed units must come from the fixed required-unit allowlist")
          if len(set(data["failedUnits"])) != len(data["failedUnits"]):
              fail("normalized failed units must be unique")
          if not isinstance(data["collectionErrors"], list) or any(not isinstance(item, str) or item not in ("zfs", "md", "smart", "owner", "units", "journal", "swap", "backup", "thermal") for item in data["collectionErrors"]):
              fail("normalized collection errors must use documented collector names")
          return data

      def collect_real():
          data = {
              "zfsHealthy": True,
              "zfsScrubHealthy": True,
              "mdHealthy": True,
              "mdScrubHealthy": True,
              "smartHealthy": True,
              "poolFull": False,
              "ownerUsageBytes": {},
              "failedUnits": [],
              "newOom": False,
              "swapUsedBytes": 0,
              "backupStale": dict((owner, False) for owner in CONFIG["ownerDatasets"]),
              "backupCapacityHigh": dict((owner, False) for owner in CONFIG["ownerDatasets"]),
              "thermalCritical": False,
              "thermalThrottling": False,
              "collectionErrors": [],
          }
          commands = CONFIG["commands"]
          try:
              health = run([commands["zpool"], "list", "-H", "-o", "health", "tank"]).stdout.strip()
              data["zfsHealthy"] = health == "ONLINE"
              available = run([commands["zfs"], "get", "-H", "-p", "-o", "value", "available", "tank"]).stdout.strip()
              data["poolFull"] = int(available) == 0
              status_output = run([commands["zpool"], "status", "tank"]).stdout
              scan_lines = [line.strip() for line in status_output.splitlines() if line.lstrip().startswith("scan:")]
              if len(scan_lines) != 1:
                  raise RuntimeError("unexpected zpool scrub status")
              scan = scan_lines[0].lower()
              if "scrub" in scan and "in progress" not in scan and "with 0 errors" not in scan:
                  data["zfsScrubHealthy"] = False
          except Exception:
              data["collectionErrors"].append("zfs")
          try:
              md = run([commands["mdadm"], "--detail", "--test", "/dev/md/root"], check=False)
              if md.returncode not in (0, 1):
                  raise RuntimeError("md status unavailable")
              data["mdHealthy"] = md.returncode == 0
              md_root = md_sysfs()
              mismatch = int((md_root / "mismatch_cnt").read_text(encoding="ascii").strip())
              action = (md_root / "sync_action").read_text(encoding="ascii").strip()
              if mismatch > 0 or action not in ("idle", "check", "repair", "resync", "recover"):
                  data["mdScrubHealthy"] = False
          except Exception:
              data["collectionErrors"].append("md")
          try:
              scan = run([commands["smartctl"], "--scan-open"])
              devices = []
              for line in scan.stdout.splitlines():
                  fields = line.split()
                  if fields and fields[0].startswith("/dev/"):
                      devices.append(fields)
              if not devices:
                  raise RuntimeError("no SMART devices discovered")
              for fields in devices:
                  command = [commands["smartctl"], "-H"]
                  if "-d" in fields:
                      position = fields.index("-d")
                      if position + 1 < len(fields):
                          command.extend(["-d", fields[position + 1]])
                  command.append(fields[0])
                  result = run(command, check=False)
                  if result.returncode & 0b11111000:
                      data["smartHealthy"] = False
                  elif result.returncode & 0b00000111:
                      raise RuntimeError("SMART command failed")
          except Exception:
              data["collectionErrors"].append("smart")
          try:
              for owner, dataset in CONFIG["ownerDatasets"].items():
                  used = run([commands["zfs"], "get", "-H", "-p", "-o", "value", "used", dataset]).stdout.strip()
                  data["ownerUsageBytes"][owner] = int(used)
          except Exception:
              data["collectionErrors"].append("owner")
              for owner in CONFIG["ownerDatasets"]:
                  data["ownerUsageBytes"].setdefault(owner, 0)
          try:
              active_required = set(CONFIG["requiredActiveUnits"])
              for unit in CONFIG["requiredUnits"]:
                  result = run([
                      commands["systemctl"], "show", unit,
                      "--property=LoadState", "--property=ActiveState", "--value",
                  ], check=False)
                  states = result.stdout.splitlines()
                  if result.returncode != 0 or len(states) != 2:
                      data["failedUnits"].append(unit)
                      continue
                  load_state, active_state = states
                  failed = load_state != "loaded" or active_state == "failed"
                  if unit in active_required and active_state not in ("active", "activating", "reloading"):
                      failed = True
                  if failed:
                      data["failedUnits"].append(unit)
          except Exception:
              data["collectionErrors"].append("units")
          now = time.time()
          cursor_dir = secure_state_dir("collector")
          cursor_path = cursor_dir / "journal-since"
          try:
              since = now
              if cursor_path.exists():
                  raw = cursor_path.read_text(encoding="ascii").strip()
                  if re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", raw) is None:
                      raise RuntimeError("invalid journal cursor")
                  since = float(raw)
              journal = run([commands["journalctl"], "-k", "--since", "@" + str(since), "--no-pager", "-o", "cat"], check=False)
              if journal.returncode not in (0, 1):
                  raise RuntimeError("journal unavailable")
              lowered = journal.stdout.lower()
              data["newOom"] = "out of memory:" in lowered or "oom-kill:" in lowered
              data["thermalCritical"] = "thermal critical" in lowered or "critical temperature" in lowered
              data["thermalThrottling"] = "thermal thrott" in lowered or "cpu clock throttled" in lowered
              smart_journal = run([commands["journalctl"], "-u", "smartd.service", "--since", "@" + str(since), "--no-pager", "-o", "cat"], check=False)
              if smart_journal.returncode not in (0, 1):
                  raise RuntimeError("smartd journal unavailable")
              smart_warning = smart_journal.stdout.lower()
              warning_markers = (
                  "failed smart", "smart failure", "critical warning", "prefail",
                  "error log entries increased", "self-test log error count increased",
              )
              if any(marker in smart_warning for marker in warning_markers):
                  data["smartHealthy"] = False
              atomic_write(cursor_dir, "journal-since", (repr(now) + "\n").encode("ascii"))
          except Exception:
              data["collectionErrors"].append("journal")
          try:
              values = {}
              with open("/proc/meminfo", "r", encoding="ascii") as handle:
                  for line in handle:
                      fields = line.split()
                      if fields and fields[0] in ("SwapTotal:", "SwapFree:"):
                          values[fields[0]] = int(fields[1]) * 1024
              data["swapUsedBytes"] = values["SwapTotal:"] - values["SwapFree:"]
          except Exception:
              data["collectionErrors"].append("swap")
          backup = CONFIG["readiness"]["backup"]
          if backup["ready"]:
              try:
                  for owner, raw_path in backup["stampFiles"].items():
                      path = check_runtime_path(raw_path)
                      data["backupStale"][owner] = now - int(path.stat().st_mtime) > backup["maxAgeSeconds"]
                  for owner, raw_path in backup["capacityFiles"].items():
                      path = check_runtime_path(raw_path)
                      percent = int(path.read_text(encoding="ascii").strip())
                      if percent < 0 or percent > 100:
                          raise RuntimeError("backup capacity percent is outside 0..100")
                      data["backupCapacityHigh"][owner] = percent >= CONFIG["backupCapacityWarningPercent"]
              except Exception:
                  data["collectionErrors"].append("backup")
          thermal = CONFIG["readiness"]["thermal"]
          if thermal["ready"]:
              try:
                  readings = []
                  for raw_path in thermal["sensorFiles"]:
                      path = check_runtime_path(raw_path)
                      readings.append(int(path.read_text(encoding="ascii").strip()))
                  data["thermalCritical"] = data["thermalCritical"] or max(readings) >= thermal["criticalMilliCelsius"]
              except Exception:
                  data["collectionErrors"].append("thermal")
          return validate_normalized(data)

      def classify(data):
          results = []
          if not data["zfsHealthy"]:
              results.append(finding("zfs-degraded", "tank", "ZFS tank is degraded", "tank did not report ONLINE"))
          if not data["zfsScrubHealthy"]:
              results.append(finding("zfs-scrub", "tank", "ZFS scrub requires attention", "the latest tank scrub was canceled or reported errors"))
          if not data["mdHealthy"]:
              results.append(finding("md-degraded", "root", "md root is degraded", "/dev/md/root did not report optimal"))
          if not data["mdScrubHealthy"]:
              results.append(finding("md-scrub", "root", "md scrub requires attention", "/dev/md/root reported mismatches or an invalid sync state"))
          if not data["smartHealthy"]:
              results.append(finding("smart-health", "internal", "SMART or NVMe health failed", "at least one internal device reported a health failure"))
          if data["poolFull"]:
              results.append(finding("pool-full", "tank", "ZFS tank is full", "tank reported no free bytes"))
          for owner in sorted(data["ownerUsageBytes"]):
              used = data["ownerUsageBytes"][owner]
              if used >= CONFIG["ownerWarningBytes"]:
                  results.append(finding("owner-usage", owner, "Owner storage warning for " + owner, "usage is at or above 180000000000 decimal bytes"))
          for unit in sorted(data["failedUnits"]):
              results.append(finding("required-unit-failed", unit, "Required unit failed", unit))
          if data["newOom"]:
              results.append(finding("oom", "kernel", "New out-of-memory event", "the kernel journal contains a new OOM event"))
          if data["swapUsedBytes"] > 0:
              results.append(finding("swap", "host", "Swap is in use", "nonzero swap use was observed"))
          for owner in sorted(data["backupStale"]):
              if data["backupStale"][owner]:
                  results.append(finding("backup-stale", owner, "Backup is stale for " + owner, "the configured owner backup stamp is stale"))
              if data["backupCapacityHigh"][owner]:
                  results.append(finding("backup-capacity", owner, "Backup device capacity warning for " + owner, "the configured owner backup device is at or above 85 percent"))
          if data["thermalCritical"]:
              results.append(finding("thermal-critical", "host", "Thermal critical condition", "a critical thermal condition was observed"))
          if data["thermalThrottling"]:
              results.append(finding("thermal-throttling", "host", "Thermal throttling observed", "thermal throttling was observed"))
          for collector in sorted(set(data["collectionErrors"])):
              results.append(finding("collection-failure", collector, "Health collection failed", collector + " collector failed; the corresponding health state is unknown"))
          return results

      def finding_key(item):
          return hashlib.sha256((item["kind"] + "\0" + item["identity"]).encode("utf-8")).hexdigest()

      def make_message(item, alert_id):
          email_cfg = CONFIG["readiness"]["email"]
          message = EmailMessage(policy=email.policy.SMTP)
          message["From"] = email_cfg["sender"]
          message["To"] = email_cfg["recipient"]
          message["Subject"] = "Balaur alert: " + item["summary"]
          message["Date"] = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
          message["Message-ID"] = "<" + alert_id + "@balaur.local>"
          message.set_content("Alert class: " + item["kind"] + "\nObserved: " + timestamp() + "\nDetail: " + item["detail"] + "\n")
          return message.as_bytes()

      def record_new_finding(item):
          alerts = secure_state_dir("alerts")
          active = secure_state_dir("active")
          key = finding_key(item)
          marker = active / key
          if marker.exists():
              info = marker.lstat()
              if (not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode)
                      or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o600):
                  fail("unsafe active alert marker")
              if CONFIG["readiness"]["email"]["ready"]:
                  alert_id = marker.read_text(encoding="ascii").strip()
                  if SAFE_ALERT_ID.fullmatch(alert_id) is None:
                      fail("invalid active alert identifier")
                  filename = alert_id + ".eml"
                  outbox = secure_state_dir("outbox")
                  sent = secure_state_dir("sent")
                  if not (outbox / filename).exists() and not (sent / filename).exists():
                      atomic_write(outbox, filename, make_message(item, alert_id))
              return
          alert_id = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ-") + uuid.uuid4().hex
          record = dict(item)
          record["id"] = alert_id
          record["observed"] = timestamp()
          atomic_write(alerts, alert_id + ".json", (json.dumps(record, sort_keys=True) + "\n").encode("utf-8"))
          if CONFIG["readiness"]["email"]["ready"]:
              atomic_write(secure_state_dir("outbox"), alert_id + ".eml", make_message(item, alert_id))
          # Commit the deduplication marker only after every durable payload.
          atomic_write(active, key, (alert_id + "\n").encode("ascii"))

      def marker_item(marker):
          info = marker.lstat()
          if (not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode)
                  or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o600):
              fail("unsafe active alert marker")
          alert_id = marker.read_text(encoding="ascii").strip()
          if SAFE_ALERT_ID.fullmatch(alert_id) is None:
              fail("invalid active alert identifier")
          record_path = secure_state_dir("alerts") / (alert_id + ".json")
          record_info = record_path.lstat()
          if (not stat.S_ISREG(record_info.st_mode) or stat.S_ISLNK(record_info.st_mode)
                  or record_info.st_uid != 0 or stat.S_IMODE(record_info.st_mode) != 0o600):
              fail("unsafe active alert record")
          with record_path.open("r", encoding="utf-8") as handle:
              record = json.load(handle)
          if not isinstance(record, dict) or not isinstance(record.get("kind"), str):
              fail("invalid active alert record")
          return record

      def apply_findings(findings, collection_errors):
          preserved_kinds = set()
          for collector in collection_errors:
              preserved_kinds.update(UNKNOWN_KINDS[collector])
          with state_lock():
              active = secure_state_dir("active")
              current = set(finding_key(item) for item in findings)
              for entry in active.iterdir():
                  if not SAFE_NAME.fullmatch(entry.name):
                      fail("unexpected active alert marker")
                  item = marker_item(entry)
                  if entry.name not in current and item["kind"] not in preserved_kinds:
                      entry.unlink()
              for item in findings:
                  record_new_finding(item)
              active_items = [marker_item(entry) for entry in active.iterdir()]
          print(json.dumps({"active": len(active_items), "classes": sorted(set(item["kind"] for item in active_items))}, sort_keys=True))

      def check_command(input_path):
          if input_path is None:
              data = collect_real()
          else:
              path = check_runtime_path(input_path)
              with path.open("r", encoding="utf-8") as handle:
                  data = validate_normalized(json.load(handle))
          apply_findings(classify(data), data["collectionErrors"])

      def snapshot_command(schedule):
          snapshots = CONFIG["snapshots"]
          retention = snapshots["retention"][schedule]
          stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
          names = [
              dataset + "@" + snapshots["namespace"] + "-" + schedule + "-" + stamp
              for dataset in snapshots["datasets"]
          ]
          existing = [
              name for name in names
              if run([CONFIG["commands"]["zfs"], "list", "-H", "-t", "snapshot", "-o", "name", name], check=False).returncode == 0
          ]
          if not existing:
              # One non-recursive invocation gives every protected leaf the same
              # atomic point-in-time snapshot without ever selecting children.
              run([CONFIG["commands"]["zfs"], "snapshot"] + names)
          elif len(existing) != len(names):
              fail("refusing to complete a partial protected snapshot set")
          for dataset in snapshots["datasets"]:
              listed = run([CONFIG["commands"]["zfs"], "list", "-H", "-p", "-d", "1", "-t", "snapshot", "-o", "name,creation", "-s", "creation", dataset]).stdout.splitlines()
              prefix = re.escape(dataset + "@" + snapshots["namespace"] + "-" + schedule + "-")
              allowed = re.compile("^" + prefix + r"[0-9]{8}T[0-9]{6}Z$")
              owned = []
              for line in listed:
                  fields = line.split("\t", 1)
                  if fields and allowed.fullmatch(fields[0]):
                      owned.append(fields[0])
              for obsolete in owned[:-retention]:
                  run([CONFIG["commands"]["zfs"], "destroy", obsolete])

      def deliver_command():
          email_cfg = CONFIG["readiness"]["email"]
          if not email_cfg["ready"]:
              fail("email delivery is not ready")
          adapter = check_runtime_path(email_cfg["adapter"], executable=True)
          with state_lock():
              outbox = secure_state_dir("outbox")
              sent = secure_state_dir("sent")
              failed = False
              for queued in sorted(outbox.iterdir()):
                  if not queued.name.endswith(".eml") or "/" in queued.name:
                      fail("unexpected outbox file")
                  info = queued.lstat()
                  if (not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode)
                          or info.st_uid != 0 or stat.S_IMODE(info.st_mode) != 0o600):
                      fail("unsafe outbox file")
                  descriptor = os.open(queued, os.O_RDONLY | os.O_NOFOLLOW)
                  try:
                      with os.fdopen(descriptor, "rb") as handle:
                          result = subprocess.run([str(adapter), "-i", email_cfg["recipient"]], stdin=handle,
                                                  stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=60, check=False)
                  except Exception as error:
                      print("balaur-monitor: adapter invocation failed: " + str(error), file=sys.stderr)
                      failed = True
                      continue
                  if result.returncode == 0:
                      os.replace(queued, sent / queued.name)
                  else:
                      print("balaur-monitor: adapter failed with status " + str(result.returncode), file=sys.stderr)
                      failed = True
              if failed:
                  raise RuntimeError("one or more queued alerts were retained after delivery failure")

      def monthly_test_command():
          if not CONFIG["readiness"]["email"]["ready"]:
              fail("monthly email test is not ready")
          item = finding("monthly-test", "email", "Monthly end-to-end test", "the configured external adapter was tested end to end")
          alert_id = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ-") + uuid.uuid4().hex
          record = dict(item)
          record["id"] = alert_id
          record["observed"] = timestamp()
          atomic_write(secure_state_dir("alerts"), alert_id + ".json", (json.dumps(record, sort_keys=True) + "\n").encode("utf-8"))
          atomic_write(secure_state_dir("outbox"), alert_id + ".eml", make_message(item, alert_id))
          deliver_command()

      def md_scrub_command():
          run([CONFIG["commands"]["mdadm"], "--action=check", "/dev/md/root"])
          deadline = time.monotonic() + 86400
          root = md_sysfs()
          while True:
              action = (root / "sync_action").read_text(encoding="ascii").strip()
              if action == "idle":
                  break
              if action not in ("check", "repair", "resync", "recover"):
                  fail("md scrub entered an unexpected sync state: " + action)
              if time.monotonic() >= deadline:
                  fail("md scrub did not complete within 24 hours")
              time.sleep(30)
          mismatch = int((root / "mismatch_cnt").read_text(encoding="ascii").strip())
          if mismatch > 0:
              item = finding("md-scrub", "root", "md scrub requires attention", "/dev/md/root completed with " + str(mismatch) + " mismatched blocks")
              with state_lock():
                  record_new_finding(item)
              fail("md scrub completed with mismatched blocks")
          print(json.dumps({"mdScrub": "complete", "mismatchBlocks": 0}, sort_keys=True))

      def md_event_command(event="DegradedArray"):
          concerning = {"DeviceDisappeared", "Fail", "FailSpare", "DegradedArray", "SparesMissing"}
          if event not in concerning:
              print(json.dumps({"mdEventHandled": event}, sort_keys=True))
              return
          item = finding("md-degraded", "root", "md root event", "mdadm reported " + event + " for /dev/md/root")
          with state_lock():
              record_new_finding(item)

      def is_mdadm_invocation(arguments):
          events = {
              "DeviceDisappeared", "RebuildStarted", "RebuildFinished", "Fail", "FailSpare",
              "SpareActive", "NewArray", "DegradedArray", "MoveSpare", "SparesMissing", "TestMessage"
          }
          return (
              len(arguments) in (3, 4)
              and (arguments[1] in events or re.fullmatch(r"Rebuild[0-9]{2}", arguments[1]) is not None)
              # mdadm may report a named /dev/md/root alias or the kernel's
              # numbered /dev/md127 path while assembling the same sole array.
              and re.fullmatch(r"/dev/md(?:/[A-Za-z0-9_.+-]+|[0-9]+)", arguments[2]) is not None
          )

      def main():
          if is_mdadm_invocation(sys.argv):
              # mdadm PROGRAM accepts one executable only and appends its Event,
              # md device, and optional component as positional arguments.
              md_event_command(sys.argv[1])
              return
          parser = argparse.ArgumentParser(prog="balaur-monitor")
          subparsers = parser.add_subparsers(dest="command", required=True)
          check_parser = subparsers.add_parser("check")
          check_parser.add_argument("--input")
          snapshot_parser = subparsers.add_parser("snapshot")
          snapshot_parser.add_argument("schedule", choices=("daily", "weekly"))
          subparsers.add_parser("deliver")
          subparsers.add_parser("monthly-test")
          subparsers.add_parser("md-scrub")
          subparsers.add_parser("md-event")
          arguments, extras = parser.parse_known_args()
          if arguments.command != "md-event" and extras:
              parser.error("unexpected arguments")
          if arguments.command == "check":
              check_command(arguments.input)
          elif arguments.command == "snapshot":
              snapshot_command(arguments.schedule)
          elif arguments.command == "deliver":
              deliver_command()
          elif arguments.command == "monthly-test":
              monthly_test_command()
          elif arguments.command == "md-scrub":
              md_scrub_command()
          elif arguments.command == "md-event":
              md_event_command()

      if __name__ == "__main__":
          try:
              main()
          except Exception as error:
              print("balaur-monitor: " + str(error), file=sys.stderr)
              sys.exit(1)
    '';
  };

  serviceDefaults = {
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      Group = "root";
      UMask = "0077";
      StateDirectory = stateDirectory;
      StateDirectoryMode = "0700";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ statePath ];
    };
  };
  persistentTimer = calendar: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = calendar;
      Persistent = true;
      RandomizedDelaySec = "15m";
    };
  };
in
{
  options.balaur.monitoring = {
    snapshots = {
      datasets = lib.mkOption {
        type = lib.types.listOf (lib.types.strMatching "^tank/[A-Za-z0-9._/-]+$");
        readOnly = true;
        default = storage.protectedLeafDatasets;
        description = "Exact non-recursive ZFS snapshot allowlist.";
      };
      retention = lib.mkOption {
        type = lib.types.submodule {
          options = {
            daily = lib.mkOption {
              type = lib.types.ints.positive;
              readOnly = true;
              default = 7;
            };
            weekly = lib.mkOption {
              type = lib.types.ints.positive;
              readOnly = true;
              default = 4;
            };
          };
        };
        readOnly = true;
        default = { };
        description = "Exact per-schedule snapshot retention.";
      };
    };
    readiness = {
      email = {
        ready = lib.mkEnableOption "external sendmail-compatible alert delivery";
        adapter = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Absolute canonical runtime path to a root-owned sendmail-compatible adapter.";
        };
        sender = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        recipient = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };
      backup = {
        ready = lib.mkEnableOption "owner backup freshness checks";
        stampFiles = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Exact owner-to-root-owned freshness stamp mapping.";
        };
        capacityFiles = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Exact owner-to-root-owned files containing integer backup-device use percentages.";
        };
        capacityWarningPercent = lib.mkOption {
          type = lib.types.ints.between 1 100;
          readOnly = true;
          default = 85;
          description = "Exact backup-device capacity warning percentage from the confirmed backup policy.";
        };
        maxAgeSeconds = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
        };
      };
      thermal = {
        ready = lib.mkEnableOption "measured numeric thermal comparisons";
        sensorFiles = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        criticalMilliCelsius = lib.mkOption {
          type = lib.types.nullOr lib.types.ints.positive;
          default = null;
        };
      };
    };
    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${monitoringProgram}/bin/balaur-monitor";
      description = "Single executable interface for collection, normalized input, snapshots, md events, and delivery.";
    };
  };

  config = {
    assertions = [
      {
        assertion =
          cfg.snapshots.datasets == storage.protectedLeafDatasets
          && lib.unique cfg.snapshots.datasets == cfg.snapshots.datasets;
        message = "monitoring snapshots must equal the unique protected-leaf allowlist exactly";
      }
      {
        assertion = lib.intersectLists cfg.snapshots.datasets storage.disposableDatasets == [ ];
        message = "monitoring snapshot targets and disposable datasets must remain exactly disjoint";
      }
      {
        assertion =
          cfg.snapshots.retention == {
            daily = 7;
            weekly = 4;
          };
        message = "monitoring snapshot retention must remain exactly 7 daily and 4 weekly";
      }
      {
        assertion = cfg.readiness.email.ready == emailComplete;
        message = "email readiness must exactly match complete adapter, sender, and recipient fields";
      }
      {
        assertion =
          !emailComplete
          || (
            absoluteCanonical cfg.readiness.email.adapter
            && noHeaderInjection cfg.readiness.email.sender
            && noHeaderInjection cfg.readiness.email.recipient
            && emailAddress cfg.readiness.email.sender
            && emailAddress cfg.readiness.email.recipient
          );
        message = "email adapter path and RFC822 addresses must be canonical and injection-safe";
      }
      {
        assertion = cfg.readiness.backup.ready == backupComplete;
        message = "backup readiness must exactly match both owner stamps and max age";
      }
      {
        assertion =
          !backupComplete
          || lib.all absoluteCanonical (
            builtins.attrValues cfg.readiness.backup.stampFiles
            ++ builtins.attrValues cfg.readiness.backup.capacityFiles
          );
        message = "backup freshness and capacity paths must be absolute and canonical";
      }
      {
        assertion = cfg.readiness.thermal.ready == thermalComplete;
        message = "thermal readiness must exactly match sensor files and a measured critical threshold";
      }
      {
        assertion = !thermalComplete || lib.all absoluteCanonical cfg.readiness.thermal.sensorFiles;
        message = "thermal sensor paths must be absolute and canonical";
      }
    ];

    warnings =
      lib.optional (!cfg.readiness.email.ready)
        "DEPLOYMENT BLOCKER: external alert email and monthly end-to-end delivery remain disabled until the Owner configures a sendmail-compatible adapter, sender, and recipient; no SMTP values were guessed."
      ++
        lib.optional (!cfg.readiness.backup.ready)
          "DEPLOYMENT BLOCKER: backup freshness/capacity checks remain disabled until issue 14 provides both Owner stamp paths, capacity status paths, and an approved maximum age; no freshness policy was guessed."
      ++
        lib.optional (!cfg.readiness.thermal.ready)
          "DEPLOYMENT BLOCKER: numeric thermal comparison remains disabled until physical sensor paths and measured critical limits are approved; journal critical/throttling detection remains active.";

    services.zfs = {
      autoSnapshot.enable = false;
      autoScrub = {
        enable = true;
        pools = [ "tank" ];
        interval = "*-*-01 02:00:00";
        randomizedDelaySec = "1h";
      };
      zed.enableMail = false;
    };

    services.smartd = {
      enable = true;
      autodetect = true;
      notifications = {
        mail.enable = false;
        systembus-notify.enable = false;
        wall.enable = false;
        x11.enable = false;
      };
    };

    # mdadm uses one PROGRAM path in both initrd and the deployed system. The
    # tiny /bin/sh bridge is copied into both: initrd events queue under /run,
    # while stage-2 events dispatch directly to the monitored interface.
    boot.swraid.mdadmConf = ''
      PROGRAM /etc/balaur-md-event
    '';
    boot.initrd.extraFiles."/etc/balaur-md-event".source = mdEventBridge;
    boot.initrd.systemd.contents."/etc/balaur-md-event".source = mdEventBridge;
    environment.etc."balaur-md-event" = {
      source = mdEventBridge;
      mode = "0755";
    };

    environment.systemPackages = [ monitoringProgram ];

    systemd.services = {
      balaur-snapshot-daily = serviceDefaults // {
        description = "Exact non-recursive daily Balaur snapshots";
        after = [ "zfs-import-tank.service" ];
        serviceConfig = serviceDefaults.serviceConfig // {
          ExecStart = "${cfg.command} snapshot daily";
        };
      };
      balaur-snapshot-weekly = serviceDefaults // {
        description = "Exact non-recursive weekly Balaur snapshots";
        after = [ "zfs-import-tank.service" ];
        serviceConfig = serviceDefaults.serviceConfig // {
          ExecStart = "${cfg.command} snapshot weekly";
        };
      };
      balaur-md-check = serviceDefaults // {
        description = "Staggered md root consistency check";
        serviceConfig = serviceDefaults.serviceConfig // {
          ExecStart = "${cfg.command} md-scrub";
          TimeoutStartSec = "1d";
          ReadWritePaths = [
            statePath
            "/sys/block"
          ];
        };
      };
      balaur-md-early-events = serviceDefaults // {
        description = "Replay md events queued by the initrd bridge";
        wantedBy = [ "multi-user.target" ];
        before = [ "balaur-monitoring-check.service" ];
        script = ''
          set -eu
          queue=/run/balaur-md-events
          test -e "$queue" || exit 0
          test ! -L "$queue"
          test "$(${pkgs.coreutils}/bin/stat -Lc '%a:%u:%g' "$queue")" = 600:0:0
          while IFS="$(${pkgs.coreutils}/bin/printf '\t')" read -r event device extra; do
            test -n "$event"
            test -n "$device"
            test -z "$extra"
            ${cfg.command} "$event" "$device"
          done < "$queue"
          ${pkgs.coreutils}/bin/rm -f "$queue"
        '';
        serviceConfig = serviceDefaults.serviceConfig // {
          ReadWritePaths = [
            statePath
            "/run"
          ];
        };
      };
      balaur-monitoring-check = serviceDefaults // {
        description = "Balaur local health classification";
        after = [
          "multi-user.target"
          "balaur-md-early-events.service"
        ];
        serviceConfig = serviceDefaults.serviceConfig // {
          ExecStart = "${cfg.command} check";
          ProtectProc = "invisible";
          ReadOnlyPaths = [ "/proc/meminfo" ];
        };
      };
    }
    // lib.optionalAttrs cfg.readiness.email.ready {
      balaur-monitoring-delivery = serviceDefaults // {
        description = "Deliver queued Balaur alerts through the configured external adapter";
        serviceConfig = serviceDefaults.serviceConfig // {
          ExecStart = "${cfg.command} deliver";
          ReadOnlyPaths = [ cfg.readiness.email.adapter ];
        };
      };
      balaur-monitoring-monthly-test = serviceDefaults // {
        description = "Monthly end-to-end Balaur alert test";
        serviceConfig = serviceDefaults.serviceConfig // {
          ExecStart = "${cfg.command} monthly-test";
          ReadOnlyPaths = [ cfg.readiness.email.adapter ];
        };
      };
    };

    systemd.timers = {
      balaur-snapshot-daily = persistentTimer "daily";
      balaur-snapshot-weekly = persistentTimer "weekly";
      balaur-md-check = persistentTimer "*-*-15 02:00:00";
      balaur-monitoring-check = persistentTimer "*:0/15";
    }
    // lib.optionalAttrs cfg.readiness.email.ready {
      balaur-monitoring-delivery = persistentTimer "*:0/5";
      balaur-monitoring-monthly-test = persistentTimer "monthly";
    };
  };
}
