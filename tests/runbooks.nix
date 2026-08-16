{ pkgs }:

let
  inherit (pkgs) lib;
  install = builtins.readFile ../docs/runbooks/install.md;
  update = builtins.readFile ../docs/runbooks/update.md;
  recovery = builtins.readFile ../docs/runbooks/recovery.md;
  readme = builtins.readFile ../README.md;
  allRunbooks = install + update + recovery;
  assertions = [
    {
      assertion =
        lib.hasInfix "STOP — not authorized for execution" install
        && lib.hasInfix "No physical invocation or `nixos-install` sequence is approved" install
        && lib.hasInfix "contains no authorized destructive invocation" readme;
      message = "draft installation documentation must stop before the destructive boundary";
    }
    {
      assertion =
        lib.hasInfix "/dev/disk/by-id/nvme-CT1000P3PSSD8_24454C2CAAFE" install
        && lib.hasInfix "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B76870B8ECD" install
        && lib.hasInfix "24454C2CAAFE" install
        && lib.hasInfix "50026B76870B8ECD" install
        && lib.hasInfix "1000204886016" install;
      message = "install observations must name both verified NVMe identities and exact size";
    }
    {
      assertion =
        lib.hasInfix "must not be restored" install
        && lib.hasInfix "Do not restore old internal service state" install;
      message = "installation must explicitly reject restoration of erased internal state";
    }
    {
      assertion =
        lib.hasInfix "restartIfChanged = false" update
        && lib.hasInfix "/srv/people/<owner>/apps/approved-versions" update
        && lib.hasInfix "Never start old application code against a database already migrated" update;
      message = "update documentation must preserve the owner migration and rollback contract";
    }
    {
      assertion =
        lib.hasInfix "Either NVMe fails" recovery
        && lib.hasInfix "Motherboard loss with both NVMe drives intact" recovery
        && lib.hasInfix "Lost root filesystem with intact `tank`" recovery
        && lib.hasInfix "Lost SSH, sudo, or age credentials" recovery
        && lib.hasInfix "Lost owner USB or Borg recovery material" recovery;
      message = "recovery documentation must cover all required host, credential, and USB-loss scenarios";
    }
    {
      assertion =
        lib.hasInfix "Deferred owner USB/Borg recovery" recovery
        && lib.hasInfix "4c83b0a2-5de3-4100-98bd-8d562149d9e0" allRunbooks
        && lib.hasInfix "off-host recovery is unproven" recovery
        && !(lib.hasInfix "mkfs.ext4 -L BALAUR_BACKUP" allRunbooks)
        && !(lib.hasInfix "borg create" allRunbooks);
      message = "deferred USB documentation must preserve the SanDisk and avoid fake operational commands";
    }
    {
      assertion =
        lib.hasInfix "Legacy pre-rebuild documentation — do not execute" readme
        && lib.hasInfix "docs/runbooks/install.md" readme
        && lib.hasInfix "docs/runbooks/recovery.md" readme
        && !(lib.hasInfix "sgdisk --delete" readme)
        && !(lib.hasInfix "mdadm --create" readme)
        && !(lib.hasInfix "mkfs.ext4 -L BALAUR_BACKUP" readme)
        && !(lib.hasInfix "borg key export" readme);
      message = "README must route operators to guarded runbooks and remove copyable legacy disk/USB commands";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur runbook invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-runbook-tests" { } ''
    ${pkgs.python3}/bin/python3 - \
      ${../docs/runbooks/install.md} \
      ${../docs/runbooks/update.md} \
      ${../docs/runbooks/recovery.md} <<'PY'
    import pathlib
    import re
    import subprocess
    import sys

    blocks = []
    for raw_path in sys.argv[1:]:
        lines = pathlib.Path(raw_path).read_text(encoding="utf-8").splitlines()
        in_fence = False
        capture = False
        current = []
        for line in lines:
            if line.startswith("```"):
                if not in_fence:
                    language = line[3:].strip()
                    in_fence = True
                    capture = language in ("", "console", "sh", "bash")
                    current = []
                else:
                    if capture:
                        blocks.append("\n".join(current))
                    in_fence = False
                    capture = False
                    current = []
            elif in_fence and capture:
                current.append(line)
        if in_fence:
            raise SystemExit("unterminated runbook code fence: " + raw_path)
    shell = "\n".join(blocks)
    result = subprocess.run(["${pkgs.bash}/bin/bash", "-n"], input=shell, text=True, check=False)
    if result.returncode != 0:
        raise SystemExit("runbook shell fences are not syntactically valid")

    forbidden = re.compile(
        r"(?:nixos-install|(?:format|disko)Script|wipefs|blkdiscard|cryptsetup|shred|"
        r"(?:^|\\s)(?:mkfs(?:\\.|\\s)|parted\\s|fdisk\\s|dd\\s|mount\\s|umount\\s)|"
        r"sgdisk\\s+--(?:delete|zap-all|clear|new|load-backup|randomize-guids)|"
        r"mdadm\\s+--(?:create|add|remove|fail|assemble|grow|stop)|"
        r"zpool\\s+(?:create|destroy|replace|attach|detach|offline|online|clear|export)|"
        r"zpool\\s+import\\s+-|"
        r"zfs\\s+(?:snapshot|rollback|destroy|set|inherit|mount|unmount|rename|promote|receive)|"
        r"borg\\s+(?:create|init|key)|<[A-Z][A-Z0-9_]*>)",
        re.MULTILINE,
    )
    match = forbidden.search(shell)
    if match is not None:
        raise SystemExit("forbidden or unresolved destructive runbook command: " + match.group(0))
    PY
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} runbook invariants passed.' > "$out/result"
  ''
