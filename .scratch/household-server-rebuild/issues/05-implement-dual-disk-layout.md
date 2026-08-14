# Implement and rehearse the dual-disk layout

Status: ready-for-agent
Blocked by: 02, 03, 04

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
