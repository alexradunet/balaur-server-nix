# Verify kernel, ZFS, ROCm, and installation tooling

Status: ready-for-agent
Blocked by: 01

## Objective

Prove the package/tooling intersection before implementation depends on it.

## Work

- Evaluate Linux 6.18 LTS with OpenZFS 2.4.3 in the chosen nixpkgs revision.
- Evaluate ROCm 7.2.x and llama.cpp support for `gfx1150`.
- Verify disko capabilities for independent dual EFI filesystems, md RAID1 ext4 root, tail slack, and a two-partition ZFS mirror.
- Record exact package versions and any required module options.
- Research literal ZFS quota units and non-recursive snapshot exclusion behavior.

## Acceptance criteria

- A small evaluation/build proof passes.
- No use of `linuxPackages_latest` remains in the target plan.
- Unsupported or uncertain behavior is documented with a tested alternative.

## Comments
