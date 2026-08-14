{
  config,
  diskoRevision,
  pkgs,
}:

assert diskoRevision == "ff8702b4de27f72b4c78573dfb89ec74e36abdf1";

pkgs.runCommand "balaur-disko-script-proof"
  {
    nativeBuildInputs = [
      pkgs.diffutils
      pkgs.gnugrep
    ];
  }
  ''
    set -eu

    format=${config.system.build.formatScript}
    disko=${config.system.build.diskoScript}

    # This check only reads generated store scripts. It never invokes either
    # script and therefore never accesses or changes a block device.
    test -x "$format"
    test -x "$disko"

    test "$(grep -cF -- '--new=1:0:+1G' "$format")" -eq 2
    test "$(grep -cF -- '--new=2:0:+128G' "$format")" -eq 2
    test "$(grep -cF -- '--new=3:0:-4G' "$format")" -eq 2

    grep -F -- 'mdadm --create "/dev/md/root"' "$format" >/dev/null
    grep -F -- '--level=1' "$format" >/dev/null
    grep -F -- 'mkfs.ext4' "$format" >/dev/null
    grep -F -- 'mode="mirror"' "$format" >/dev/null
    grep -F -- 'zpool create -f "tank"' "$format" >/dev/null
    grep -F -- 'mountpoint=/boot' "$format" >/dev/null
    grep -F -- 'mountpoint=/boot-fallback' "$format" >/dev/null

    # The destructive wrapper must enumerate only the two researched by-id
    # targets. by-partlabel paths used for their child partitions are expected.
    grep -hEo '/dev/disk/by-id/nvme-[A-Za-z0-9_.-]+' "$format" "$disko" \
      | sort -u > actual-targets
    printf '%s\n' \
      '/dev/disk/by-id/nvme-CT1000P3PSSD8_24454C2CAAFE' \
      '/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B76870B8ECD' \
      | sort > expected-targets
    diff -u expected-targets actual-targets

    # Inspect the pinned disko destroy helper reached by the wrapper and prove
    # that the generated path is visibly destructive without executing it.
    deactivate=$(grep -Eo '/nix/store/[^ ]+-disk-deactivate/disk-deactivate' "$disko" | head -n1)
    test -x "$deactivate"
    destroy_rules="$(dirname "$deactivate")/disk-deactivate.jq"
    grep -F -- 'wipefs --all -f' "$destroy_rules" >/dev/null
    grep -F -- 'dd if=/dev/zero' "$destroy_rules" >/dev/null
    grep -F -- 'zpool destroy -f' "$destroy_rules" >/dev/null

    mkdir -p "$out"
    cp expected-targets "$out/physical-targets"
    printf '%s\n' \
      'Generated format and destructive scripts built and passed static inspection.' \
      > "$out/result"
  ''
