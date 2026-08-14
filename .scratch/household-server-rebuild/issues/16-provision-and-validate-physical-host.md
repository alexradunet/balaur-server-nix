# Provision and validate the physical host

Status: ready-for-human
Blocked by: 02, 05, 15

## Objective

Execute the reviewed destructive installation only after every pre-wipe gate passes.

## Preconditions

- Clean reviewed branch; flake checks, full build, storage/container/network/backup VM tests pass.
- Offline age/Borg/recovery package exists and has been checked.
- Existing backup media is physically disconnected.
- Installer revision and both wipe-target NVMe serials are recorded.

## Work

Follow the install runbook, type-confirm both serials, install, then prove boot from each EFI and degraded md/ZFS operation with one drive absent at a time. Restore both drives and wait for full synchronization/resilvering before applications are enabled.

## Acceptance criteria

- Both independent boot paths work.
- md and ZFS are healthy after recovery tests.
- Dataset properties, quotas, mountpoints, ARC cap, snapshots, and scrubs match the spec.
- No old internal data was restored.

## Comments
