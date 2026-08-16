# Household rebuild installation runbook (draft)

> **STOP — not authorized for execution.** The current configuration is deliberately non-deployable. Issue 14 is deferred, the offline recovery package and production secrets do not exist, bootstrap passwordless sudo is still enabled, and issue 16 has not approved a physical installation. This draft contains no destructive invocation.

This runbook records the safe observations and abort gates that must precede the human-led issue-16 installation. It does not grant wipe authority. Existing internal application and media data will be erased and **must not be restored**; the attached pre-rebuild USB backup must remain untouched.

## Reviewed inputs

At the time this draft was written, `flake.lock` pinned:

- nixpkgs `ee48b147c18c7de1e6ec97dc74792be42724bed1`;
- disko `ff8702b4de27f72b4c78573dfb89ec74e36abdf1`;
- sops-nix `a8627b21b9107c5711c96b84f32a9a4b3d45295f`.

Issue 16 must record the actual installation commit and installer media rather than assuming these values are still current:

```text
Installation commit: <RECORD_GIT_COMMIT>
Installer filename: <RECORD_INSTALLER_MEDIA>
Trusted installer source/signature page: <RECORD_INDEPENDENT_SOURCE>
Expected SHA-256 from that source: <RECORD_EXPECTED_SHA256>
Installation UTC date: <RECORD_DATE>
Operator: <RECORD_OPERATOR>
```

Abort if any field remains unresolved. From a trusted checkout, record and verify without activating anything:

Set these two values from the recorded independent source; the literal sentinel values deliberately fail:

```console
INSTALLER_IMAGE='/replace/with/absolute/installer-path'
EXPECTED_INSTALLER_SHA256='REPLACE_WITH_64_HEX_DIGITS_FROM_TRUSTED_SOURCE'
test -f "$INSTALLER_IMAGE"
printf '%s' "$EXPECTED_INSTALLER_SHA256" | grep -Eq '^[0-9a-fA-F]{64}$'
printf '%s  %s\n' "$EXPECTED_INSTALLER_SHA256" "$INSTALLER_IMAGE" | sha256sum --check --strict -
git status --short
git rev-parse HEAD
nix flake check -L path:$PWD
nix build --no-link path:$PWD#nixosConfigurations.balaur.config.system.build.toplevel
nix build --no-link path:$PWD#checks.x86_64-linux.disko-scripts
nix build --no-link path:$PWD#checks.x86_64-linux.disko-install
```

Abort on a dirty checkout, an unexpected commit, an installer hash mismatch, or any failed evaluation/build/test.

## Preconditions that are currently unsatisfied

Do not proceed until all are true:

- issue 14's declarative device-bound workflow and disposable VM failure tests are complete, or the confirmed architecture has been explicitly revised by the Owner; physical USB provisioning/restore drills remain issue-17 work after installation;
- the offline administrator recovery package exists and has been checked;
- the dedicated age identity, encrypted host/owner payloads, and Alex's yescrypt hash exist through the reviewed sops-nix contract;
- password-authenticated `sudo` has been tested in a second Alex SSH session and `balaur.access.bootstrapPasswordlessSudo` is false;
- Samba, qBittorrent, personal-stack, and any enabled llama credentials are supplied only through their approved runtime paths;
- the router reservation for `192.168.50.2`, LAN/WireGuard DNS policy, and absence of WAN forwards have been reviewed;
- all USB storage, especially the preserved SanDisk below, is physically disconnected.

Never provision or wipe this preserved device:

```text
/dev/disk/by-id/usb-USB_SanDisk_3.2Gen1_00017730081925061541-0:0
size 123009761280 bytes; label BALAUR_BACKUP
UUID 4c83b0a2-5de3-4100-98bd-8d562149d9e0
```

## Wipe-target observation

The only configured whole-disk targets are:

| Role | Stable by-id | Expected model | Serial | Expected bytes |
| --- | --- | --- | --- | ---: |
| Primary | `/dev/disk/by-id/nvme-CT1000P3PSSD8_24454C2CAAFE` | `CT1000P3PSSD8` | `24454C2CAAFE` | `1000204886016` |
| Fallback | `/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B76870B8ECD` | `SNV3S1000G` | `50026B76870B8ECD` | `1000204886016` |

Linux names such as `/dev/nvme0n1` are observation-only. On the installer, redisplay both stable links, model, serial, byte/sector sizes, SMART state, and partition tables:

```console
lsblk -b -d -o PATH,SIZE,LOG-SEC,PHY-SEC,MODEL,SERIAL,TRAN
readlink -f /dev/disk/by-id/nvme-CT1000P3PSSD8_24454C2CAAFE
readlink -f /dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B76870B8ECD
TOOL_NIXPKGS='github:NixOS/nixpkgs/ee48b147c18c7de1e6ec97dc74792be42724bed1'
sudo nix shell "$TOOL_NIXPKGS#nvme-cli" -c nvme smart-log /dev/disk/by-id/nvme-CT1000P3PSSD8_24454C2CAAFE
sudo nix shell "$TOOL_NIXPKGS#nvme-cli" -c nvme smart-log /dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B76870B8ECD
sudo nix shell "$TOOL_NIXPKGS#gptfdisk" -c sgdisk --print /dev/disk/by-id/nvme-CT1000P3PSSD8_24454C2CAAFE
sudo nix shell "$TOOL_NIXPKGS#gptfdisk" -c sgdisk --print /dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B76870B8ECD
```

Abort if either stable link is absent, any identity or size differs, SMART reports a critical warning/media error, an unexpected removable device is attached, or the operator cannot explain every displayed filesystem.

Immediately before destruction, the human must type both serials from the current display—not copy them from this document. The reviewed issue-16 checklist must compare the typed values with the live devices.

## Destructive boundary

`config.system.build.formatScript` and `config.system.build.diskoScript` are destructive executable outputs. Static tests prove they contain `wipefs`, zeroing, and pool-destruction operations. They do not provide a safe `--help` or dry-run interface: invoking either output starts its operation immediately.

**No physical invocation or `nixos-install` sequence is approved by the repository yet.** Issue 16 must insert the exact command only after it has been reviewed against the chosen installer media and rehearsed interface. Do not improvise from disko examples, do not invoke a generated script to inspect it, and do not use the legacy README partition commands.

The intended resulting topology, already proved only on disposable VM disks, is:

- independent 1 GiB ESPs at `/boot` and `/boot-fallback`;
- ext4 `/` on RAID1 `/dev/md/root` with 128 GiB members;
- mirrored ZFS pool `tank` on the remaining partition of each NVMe;
- exactly 4 GiB binary tail slack on each NVMe.

## Post-install observation

After the reviewed issue-16 procedure boots the target, observe before enabling applications:

```console
for target in / /boot /boot-fallback; do mountpoint "$target" && findmnt --mountpoint "$target" || exit 1; done
cat /proc/mdstat
sudo mdadm --detail /dev/md/root
sudo zpool status -P tank
sudo zfs list -o name,mountpoint,canmount,mounted
sudo zfs get -H -p quota tank/users/alex tank/users/andreea
cat /sys/module/zfs/parameters/zfs_arc_max
test -e /boot/EFI/BOOT/BOOTX64.EFI
test -e /boot-fallback/EFI/BOOT/BOOTX64.EFI
systemctl list-timers 'balaur-*' zfs-scrub.timer
```

Expected owner quotas are exactly `220000000000` bytes and `zfs_arc_max` is `8589934592` bytes. Verify all protected/disposable mounts against `modules/storage.nix` and the disposable install VM assertions.

Issue 16 must then boot with each drive physically absent, one at a time, and record independent EFI boot plus degraded md/ZFS operation. Restore both drives and wait for complete md synchronization and ZFS resilvering before enabling applications. Do not simulate failure with unreviewed `mdadm` or ZFS mutation commands.

Finally verify private DNS/TLS, firewall listeners, monitoring, and fresh Home Assistant/Jellyfin onboarding. Do not restore old internal service state, media, downloads, models, caches, or temporary data.
