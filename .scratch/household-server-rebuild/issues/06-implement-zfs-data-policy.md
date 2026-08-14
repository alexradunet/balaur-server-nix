# Implement ZFS datasets, quotas, and resource policy

Status: ready-for-agent
Blocked by: 03, 05

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
