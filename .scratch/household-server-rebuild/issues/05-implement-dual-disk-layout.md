# Implement and rehearse the dual-disk layout

Status: ready-for-agent
Blocked by: 02, 03, 04
Completed: 2026-08-14

## Objective

Declare the destructive two-NVMe layout and prove degraded boot/storage behavior in disposable VMs.

## Work

- Add disko layout using verified by-id inputs.
- Per drive: 1 GiB EFI, 128 GiB md member, ZFS member, fixed tail slack.
- Build ext4 root on md RAID1 and `tank` on a two-device ZFS mirror.
- Install GRUB independently to both EFI filesystems.
- Keep internal storage unencrypted.
- Add a UEFI VM rehearsal with two disposable disks.

## Acceptance criteria

- Generated destructive commands are inspectable and target only explicit devices.
- VM boots from either EFI with the other disk absent.
- md root assembles degraded from either member.
- ZFS imports degraded from either member.
- No command is run against physical disks in this ticket.

## Comments

Implemented with disko revision `ff8702b4de27f72b4c78573dfb89ec74e36abdf1` and the observed NVMe by-id paths. Each disk receives a 1 GiB ESP, 128 GiB md root member, mirrored-ZFS member, and 4 GiB binary tail slack. Static generated-script checks prove exact destructive targets and topology without execution.

The disposable two-disk UEFI install test formats virtual disks, boots ext4 on md RAID1, imports a mirrored `tank`, mounts both ESPs, and verifies GRUB fallback payloads. This does not prove physical either-drive boot or degraded recovery; those remain mandatory human gates in issue 16. The resulting target configuration is buildable but must not be deployed on the current installation.
