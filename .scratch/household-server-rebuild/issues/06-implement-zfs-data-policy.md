# Implement ZFS datasets, quotas, and resource policy

Status: ready-for-agent
Blocked by: 03, 05
Completed: 2026-08-14

## Objective

Encode protected owner storage, shared storage, and disposable state so backup/snapshot exclusions follow structural boundaries.

## Work

- Create owner parent trees with `home` and `apps` children.
- Apply a byte-exact 220 GB decimal cap across each owner's live tree and a 180 GB warning threshold.
- Create protected shared/service datasets.
- Create explicit disposable datasets for media, downloads, models, caches, and temporary files.
- Cap ZFS ARC near 8 GiB.
- Remove old app-data, personal, and split-media ext4 mount assumptions.

## Acceptance criteria

- Each quota covers both owner home and application state.
- Unused owner capacity remains available to the pool.
- Disposable paths cannot be selected by broad protected snapshot/backup manifests.
- Dataset mountpoints and properties are asserted by tests.

## Comments

Implemented the host-imported `modules/storage.nix` policy seam. `config.balaur.storage` now exposes typed, read-only values for the exact 220,000,000,000-byte owner quota, 180,000,000,000-byte warning threshold, explicit protected leaf allowlist, and explicit disposable dataset list. The same leaf declarations generate the disko datasets, so later snapshot, monitoring, and backup tickets can consume the policy without reconstructing path lists.

The disposable UEFI install VM proved the complete 16-dataset tree on a mirrored `tank`, `ashift=12`, inherited compression/checksum/xattr/ACL/atime properties, exact parsable parent quota values, non-mounted structural parents, all eleven leaf mount sources and paths, safe leaf execution/device/setuid properties, an active non-racing `zfs-mount.service`, Alex home ownership/write access, and `/sys/module/zfs/parameters/zfs_arc_max=8589934592`. Leaf `canmount=noauto` deliberately leaves mandatory systemd mount units in charge; none of these mounts is `nofail`, so a missing pool or dataset cannot silently redirect a later service onto md root.

Evidence: `nix flake check -L`, the full `nixosConfigurations.balaur.config.system.build.toplevel` build, nixfmt, and `git diff --check` passed on 2026-08-14. The flake check includes the static destructive-script inspection and disposable disko install test; no generated destructive script was executed against physical devices.

Deferred: issue 07 must create Andreea and set her final home/apps ownership without inventing credentials here. Issues 13 and 14 still own snapshots, retention, monitoring/alerts, and USB backups; this ticket creates no recursive snapshot operation, timer, backup, or monitoring job. Physical pool creation/import, either-device failure behavior, degraded boot, resilvering, and deployed quota/ARC verification remain issue-16 safety gates.
