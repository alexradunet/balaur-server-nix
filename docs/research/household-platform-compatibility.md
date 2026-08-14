# Household platform compatibility

Verified: 2026-08-14

This is the bounded package and layout proof for issue 03. It changed no disk,
filesystem, service, secret, flake input, or implementation file. The only
non-repository proof file was `/tmp/household-disko-proof.nix`; its device names
are deliberately nonexistent.

## Result

The selected intersection is feasible on `x86_64-linux`:

- nixpkgs `ee48b147c18c7de1e6ec97dc74792be42724bed1` evaluates and builds Linux
  `6.18.43` with the OpenZFS `2.4.3` kernel module.
- The same nixpkgs evaluates and builds llama.cpp `9190` with ROCm `7.2.3`, HIP
  enabled, and only `gfx1150` as its HIP architecture.
- disko revision `ff8702b4de27f72b4c78573dfb89ec74e36abdf1`
  (version `1.13.0`, `released = false`) evaluates and builds scripts for two
  independent FAT ESPs, a two-member md RAID1 with ext4 `/`, fixed tail slack,
  and a two-member mirrored ZFS pool.
- Literal `quota=220000000000` is 220,000,000,000 bytes. On an owner parent it
  covers the parent, all child filesystems, and their snapshots. `refquota`
  would not meet that requirement.
- Protected datasets must be snapshotted from an explicit allowlist without
  `-r`; recursive snapshots would include every descendant, including later or
  disposable datasets.

These are evaluation/build results, not hardware runtime, degraded-boot,
resilver, model, or destructive-install tests. Those remain later safety gates.

## Pinned Linux and OpenZFS

The repository's `flake.lock` pins nixpkgs to
`ee48b147c18c7de1e6ec97dc74792be42724bed1`. The pinned source defines ZFS 2.4.3,
its kernel-module attribute as `zfs_2_4`, and its supported kernel range as
4.18 through 7.0. It also carries the upstream fix for OpenZFS issue 18366:
[`pkgs/os-specific/linux/zfs/2_4.nix`](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/pkgs/os-specific/linux/zfs/2_4.nix).
Kernel.org lists 6.18 as a longterm branch with projected EOL December 2028:
[Active kernel releases](https://kernel.org/releases.html).

Evaluation command (line wrapping added only here):

```console
$ nix eval --impure --json --expr '
  let f = builtins.getFlake (toString /home/alex/balaur-server-nix);
      pkgs = import f.inputs.nixpkgs { system = "x86_64-linux"; };
      lp = pkgs.linuxPackages_6_18;
      z = lp.${pkgs.zfs.kernelModuleAttribute};
  in { nixpkgsRevision = f.inputs.nixpkgs.rev;
       kernelVersion = lp.kernel.version; kernelDrv = lp.kernel.drvPath;
       zfsVersion = z.version; zfsModuleAttribute = pkgs.zfs.kernelModuleAttribute;
       zfsDrv = z.drvPath; zfsBroken = z.meta.broken or false; }'
{"kernelDrv":"/nix/store/falaxf4spm1xf4i0m179rv8xcnk7l51k-linux-6.18.43.drv","kernelVersion":"6.18.43","nixpkgsRevision":"ee48b147c18c7de1e6ec97dc74792be42724bed1","zfsBroken":false,"zfsDrv":"/nix/store/1787rbsyacalgj0jz4rb5hz8lxyhzkvc-zfs-kernel-2.4.3-6.18.43.drv","zfsModuleAttribute":"zfs_2_4","zfsVersion":"2.4.3"}
```

NixOS option-selection proof:

```console
$ nix eval --impure --json --expr '<nixosSystem with boot.kernelPackages = pkgs.linuxPackages_6_18; boot.zfs.package = pkgs.zfs_2_4; boot.supportedFilesystems = [ "zfs" ];>'
{"enabled":true,"kernel":"6.18.43","module":"2.4.3","moduleDrv":"/nix/store/1787rbsyacalgj0jz4rb5hz8lxyhzkvc-zfs-kernel-2.4.3-6.18.43.drv","userland":"2.4.3"}

$ nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake (toString /home/alex/balaur-server-nix);
      pkgs = import f.inputs.nixpkgs { system = "x86_64-linux"; };
  in pkgs.linuxPackages_6_18.kernel'
/nix/store/a493j0zfbm4gif5nj5jvivhlblvaq06q-linux-6.18.43

$ nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake (toString /home/alex/balaur-server-nix);
      pkgs = import f.inputs.nixpkgs { system = "x86_64-linux"; };
  in pkgs.linuxPackages_6_18.${pkgs.zfs.kernelModuleAttribute}'
/nix/store/vg4jp201fd8s8i7cgipk2pplnqjrl9lb-zfs-kernel-2.4.3-6.18.43
```

NixOS automatically selects `boot.kernelPackages.${package.kernelModuleAttribute}`
for `boot.zfs.modulePackage`; see the pinned
[`zfs.nix`](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/tasks/filesystems/zfs.nix).
Implementation should therefore pin `boot.kernelPackages = pkgs.linuxPackages_6_18`
and `boot.zfs.package = pkgs.zfs_2_4`; it must not use
`linuxPackages_latest`.

Caveat: this proves evaluation and compilation against the exact kernel, not
pool import or failure recovery on the physical host.

## ROCm and llama.cpp for `gfx1150`

Pinned nixpkgs packages llama.cpp build `9190`; `clr`, `rocblas`, and `hipblas`
all evaluate as ROCm `7.2.3`. The package accepts `rocmGpuTargets` and maps it to
`CMAKE_HIP_ARCHITECTURES`; see the pinned
[`llama-cpp/package.nix`](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/pkgs/by-name/ll/llama-cpp/package.nix).
The pinned ROCm scope includes `gfx1150` in its gfx11 targets:
[`rocm-modules/default.nix`](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/pkgs/development/rocm-modules/default.nix).
AMD's release source also identifies the
[`rocm-7.2.3` release](https://github.com/ROCm/rocm-systems/releases/tag/rocm-7.2.3).

```console
$ nix eval --impure --json --expr '
  let f = builtins.getFlake (toString /home/alex/balaur-server-nix);
      pkgs = import f.inputs.nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; };
      p = pkgs.llama-cpp.override { rocmSupport = true; rocmGpuTargets = [ "gfx1150" ]; };
  in { llamaVersion=p.version; drv=p.drvPath; rocmClr=pkgs.rocmPackages.clr.version;
       hipblas=pkgs.rocmPackages.hipblas.version; rocblas=pkgs.rocmPackages.rocblas.version;
       cmakeFlags=p.cmakeFlags; broken=p.meta.broken or false; }'
```

The result was `llamaVersion = "9190"`, all three ROCm components were
`"7.2.3"`, `broken = false`, and the flags included:

```text
-DGGML_HIP:BOOL=TRUE
-DCMAKE_HIP_ARCHITECTURES:STRING=gfx1150
```

Build and executable proof:

```console
$ nix build --impure --no-link --print-out-paths --expr '
  let f = builtins.getFlake (toString /home/alex/balaur-server-nix);
      pkgs = import f.inputs.nixpkgs { system = "x86_64-linux"; config.allowUnfree = true; };
  in pkgs.llama-cpp.override { rocmSupport = true; rocmGpuTargets = [ "gfx1150" ]; }'
/nix/store/9czd5360c6mmqgsdwyc18bkqy888498k-llama-cpp-9190

$ /nix/store/9czd5360c6mmqgsdwyc18bkqy888498k-llama-cpp-9190/bin/llama-server --version
version: 9190 (b64739e)
built with GNU 15.2.0 for Linux x86_64
```

The output contains `lib/libggml-hip.so`. `nix log` showed HIP objects such as
`/build/mmvf-gfx1150-209a47.o` and
`/build/mmq-instance-mxfp4-gfx1150-985ed6.o` completing successfully.

Required package shape:

```nix
pkgs.llama-cpp.override {
  rocmSupport = true;
  rocmGpuTargets = [ "gfx1150" ];
}
```

Caveat: no model was loaded and no Radeon runtime/offload, unified-memory,
router, idle-unload, throughput, or Jellyfin-contention behavior was tested.
Those belong to issue 10. This proof establishes package feasibility only.

## Disko proof

The tested disko revision is
[`ff8702b4de27f72b4c78573dfb89ec74e36abdf1`](https://github.com/nix-community/disko/tree/ff8702b4de27f72b4c78573dfb89ec74e36abdf1).
Its [`version.nix`](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/version.nix)
reports `1.13.0` and `released = false`; pin the revision rather than relying on
a moving branch.

`/tmp/household-disko-proof.nix` declares, on each fake disk, a `1G` EF00 FAT
filesystem, a `128G` mdraid member, and a final ZFS member with:

```nix
size = "100%";
end = "-16G";
```

The two ESP mountpoints are `/boot` and `/boot-fallback`. Both mdraid members use
`name = "root"`; `disko.devices.mdadm.root.level = 1` contains ext4 mounted at
`/`. Both ZFS members use `pool = "tank"`; the zpool has `mode = "mirror"`.

The corrected output attributes are
`host.config.system.build.formatScript` and
`host.config.system.build.diskoScript`, not
`host.config.system.build.createScript`. Disko publishes these through
[`module.nix`](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/module.nix).

```console
$ nix eval --impure --json --file /tmp/household-disko-proof.nix \
    --apply 'x: builtins.removeAttrs x ["generated"]'
{"diskoRevision":"ff8702b4de27f72b4c78573dfb89ec74e36abdf1","diskoScript":"/nix/store/gmyy26c7vj40vgjmfwgkpgwblwywh88h-disko.drv","fileSystems":["/","/boot","/boot-fallback"],"formatScript":"/nix/store/bjxnd9bn9s823m2rcnzjgv0m0dvi81dn-disko-format.drv","mdLevel":1,"nixpkgsRevision":"ee48b147c18c7de1e6ec97dc74792be42724bed1","poolMode":"mirror","quota":"220000000000","tailEnds":{"a":"-16G","b":"-16G"}}

$ nix build --impure --no-link --print-out-paths --file \
    /tmp/household-disko-proof.nix generated.format
/nix/store/kjcmx1zr5hr44mgn1xipybfhivrrvsfy-disko-format

$ nix build --impure --no-link --print-out-paths --file \
    /tmp/household-disko-proof.nix generated.disko
/nix/store/8d32sby0pwslnrzv34zsxdgv0rnndb5i-disko
```

The generated format script contains, once per disk:

```text
--new=1:0:+1G
--new=2:0:+128G
--new=3:0:-16G
mkfs.vfat ...disk-nvmeA-ESP
mkfs.vfat ...disk-nvmeB-ESP
```

It appends both root members to `raid_root`, then emits
`mdadm --create /dev/md/root --level=1 --raid-devices=<line count>` followed by
`mkfs.ext4 /dev/md/root`. It appends both tank members to `zfs_tank`, sets
`topology="mirror ${zfs_devices[*]}"`, and passes that topology to
`zpool create`.

Therefore `size = "100%"` plus an explicit `end = "-16G"` is valid in this
revision. `size = "100%"` gives the partition last-place priority, while the
explicit `end` overrides its default `-0`; the generated `sgdisk` boundary is
exactly `-16G`. See
[`lib/types/gpt.nix`](https://github.com/nix-community/disko/blob/ff8702b4de27f72b4c78573dfb89ec74e36abdf1/lib/types/gpt.nix).

The `16G` value proves fixed slack syntax; it is not a newly settled capacity
choice. Issue 05 must select and record the final fixed slack against the
observed disk sizes. In `sgdisk` syntax `G` is binary GiB, as are the `1G` and
`128G` partition sizes.

Disko creates and mounts the two independent ESP filesystems, but GRUB
replication is a separate NixOS concern. Use `boot.loader.grub.mirroredBoots`
with one entry for each mountpoint/device; the pinned NixOS option explicitly
says it mirrors boot configuration and installs GRUB to the respective devices:
[`grub.nix`](https://github.com/NixOS/nixpkgs/blob/ee48b147c18c7de1e6ec97dc74792be42724bed1/nixos/modules/system/boot/loader/grub/grub.nix).
Physical one-disk boot still requires rehearsal.

## Exact quota semantics

OpenZFS 2.4 documents `quota` as a hard limit on a dataset and all descendants,
including descendant filesystems and snapshots. It documents `refquota` as a
limit on only the dataset, excluding descendants, filesystems, and snapshots:
[`zfsprops(7)` 2.4](https://openzfs.github.io/openzfs-docs/man/v2.4/7/zfsprops.7.html).
The parent's `used` value is the amount consumed by it and all descendants and
is the value checked against its quota.

OpenZFS documents unsuffixed numeric values as exact values and suffixed values
as human-readable binary units:
[`zfs-set(8)` 2.4](https://openzfs.github.io/openzfs-docs/man/v2.4/8/zfs-set.8.html).
In the 2.4.3 parser, an empty suffix yields shift zero, so the integer is not
scaled:
[`libzfs_util.c` at zfs-2.4.3](https://github.com/openzfs/zfs/blob/zfs-2.4.3/lib/libzfs/libzfs_util.c).
Thus:

```text
quota=220000000000
```

means exactly 220,000,000,000 bytes (220 GB decimal, about 204.89 GiB), not
220 GiB. Verify deployed values with parsable output:

```console
zfs get -Hp -o name,property,value,source quota tank/users/alex tank/users/andreea
```

Set `quota` locally on each owner parent (`tank/users/alex` and
`tank/users/andreea`). Do not substitute `refquota`. Child quotas may add tighter
limits but cannot override the ancestor limit. Because snapshots count against
the parent quota, quota warnings must account for retained snapshot use.

## Safe snapshots

OpenZFS's synopsis permits multiple `dataset@snapname` operands in one command,
and says `-r` recursively creates snapshots of all descendant datasets:
[`zfs-snapshot(8)` 2.4](https://openzfs.github.io/openzfs-docs/man/v2.4/8/zfs-snapshot.8.html).
Recursive snapshots of `tank/users`, either owner parent, or a broad shared
parent are therefore unsafe: they select disposable descendants now and any new
descendant added later.

Use a declarative allowlist of protected leaf datasets and omit `-r`, for
example:

```console
zfs snapshot \
  tank/users/alex/home@daily-... \
  tank/users/alex/apps@daily-... \
  tank/users/andreea/home@daily-... \
  tank/users/andreea/apps@daily-...
```

Add approved protected shared/application datasets explicitly. Never generate
the list by recursively walking a parent. Apply retention/destruction to the
same allowlist, also without recursive parent operations. This is fail-closed:
a newly created disposable child is not protected unless deliberately added.

## Corrections and implementation constraints

1. The Linux/OpenZFS assumption is confirmed, but it must be expressed with
   `linuxPackages_6_18` and `zfs_2_4`, not `linuxPackages_latest` or the removed
   `linuxPackages.zfs` alias.
2. ROCm/llama.cpp compilation for `gfx1150` is confirmed; runtime and unified
   memory remain unproven and must not be inferred from this build.
3. The prior disko failure was only a wrong output attribute. The correct
   `system.build.formatScript` and `system.build.diskoScript` both build.
4. `size = "100%"; end = "-<size>";` is supported and emits the requested tail
   boundary. The demonstrated `16G` is not yet the final slack policy.
5. Independent ESP creation does not itself install duplicate GRUB payloads;
   configure `boot.loader.grub.mirroredBoots` and retain the physical boot test.
6. The settled 220 GB owner maximum requires parent `quota=220000000000`, not
   `220G` (binary) and not `refquota`.
7. Snapshot policy must be explicit and non-recursive. Parent quota placement
   and leaf snapshot selection intentionally differ.

No settled design requires reversal. The caveats above narrow what later issues
may claim from these proofs.
