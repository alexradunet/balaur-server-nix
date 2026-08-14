{ config, pkgs }:

let
  inherit (pkgs) lib;
  devices = config.disko.devices;
  tank = devices.zpool.tank;
  policy = config.balaur.storage;

  expectedDevices = {
    crucial = "/dev/disk/by-id/nvme-CT1000P3PSSD8_24454C2CAAFE";
    kingston = "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B76870B8ECD";
  };
  expectedPartitions = [
    {
      index = 1;
      name = "ESP";
      size = "1G";
      end = "+1G";
      type = "EF00";
      contentType = "filesystem";
    }
    {
      index = 2;
      name = "root";
      size = "128G";
      end = "+128G";
      type = "FD00";
      contentType = "mdraid";
    }
    {
      index = 3;
      name = "tank";
      size = "100%";
      end = "-4G";
      type = "BF01";
      contentType = "zfs";
    }
  ];
  partitionShape =
    disk:
    map
      (partition: {
        inherit (partition)
          name
          size
          end
          type
          ;
        index = partition._index;
        contentType = partition.content.type;
      })
      (lib.sort (left: right: left._index < right._index) (builtins.attrValues disk.content.partitions));

  expectedProtected = [
    "tank/users/alex/home"
    "tank/users/alex/apps"
    "tank/users/andreea/home"
    "tank/users/andreea/apps"
    "tank/shared"
    "tank/services"
  ];
  expectedDisposable = [
    "tank/disposable/media"
    "tank/disposable/downloads"
    "tank/disposable/models"
    "tank/disposable/cache"
    "tank/disposable/temp"
  ];
  expectedMounts = {
    "/home/alex" = "tank/users/alex/home";
    "/home/andreea" = "tank/users/andreea/home";
    "/srv/people/alex/apps" = "tank/users/alex/apps";
    "/srv/people/andreea/apps" = "tank/users/andreea/apps";
    "/srv/shared" = "tank/shared";
    "/srv/services" = "tank/services";
    "/srv/media" = "tank/disposable/media";
    "/srv/downloads" = "tank/disposable/downloads";
    "/srv/models" = "tank/disposable/models";
    "/srv/cache" = "tank/disposable/cache";
    "/srv/temp" = "tank/disposable/temp";
  };
  expectedDatasets = [
    "__root"
    "disposable"
    "disposable/cache"
    "disposable/downloads"
    "disposable/media"
    "disposable/models"
    "disposable/temp"
    "services"
    "shared"
    "users"
    "users/alex"
    "users/alex/apps"
    "users/alex/home"
    "users/andreea"
    "users/andreea/apps"
    "users/andreea/home"
  ];
  structuralDatasets = [
    "users"
    "users/alex"
    "users/andreea"
    "disposable"
  ];
  leafDatasets = map (name: lib.removePrefix "tank/" name) (expectedProtected ++ expectedDisposable);
  obsoleteMounts = [
    "/srv/app-data"
    "/srv/personal"
    "/srv/media/ssd0"
    "/srv/media/ssd1"
    "/tank"
    "/home/alex/files"
    "/home/andreea/files"
  ];
  grubBoots = config.boot.loader.grub.mirroredBoots;
  assertions = [
    {
      assertion =
        config.boot.kernelPackages.kernel.version == pkgs.linuxPackages_6_18.kernel.version
        && config.boot.zfs.package.version == pkgs.zfs_2_4.version;
      message = "Linux 6.18 and OpenZFS 2.4 must be the explicit target compatibility pair";
    }
    {
      assertion =
        builtins.mapAttrs (_: disk: disk.device) devices.disk == expectedDevices
        && lib.all (disk: partitionShape disk == expectedPartitions) (builtins.attrValues devices.disk);
      message = "both observed NVMe devices must have exact ESP, md root, ZFS, and 4 GiB-tail layouts";
    }
    {
      assertion =
        lib.all (disk: disk.content.partitions.root.content.name == "root") (
          builtins.attrValues devices.disk
        )
        && devices.mdadm.root.level == 1
        && devices.mdadm.root.content.type == "filesystem"
        && devices.mdadm.root.content.format == "ext4"
        && devices.mdadm.root.content.mountpoint == "/";
      message = "both 128 GiB members must form md RAID1 /dev/md/root with ext4 root";
    }
    {
      assertion =
        lib.all (disk: disk.content.partitions.tank.content.pool == "tank") (
          builtins.attrValues devices.disk
        )
        && tank.mode == "mirror"
        && tank.options == { ashift = "12"; }
        &&
          tank.rootFsOptions == {
            acltype = "posixacl";
            atime = "off";
            canmount = "off";
            checksum = "on";
            compression = "lz4";
            devices = "off";
            mountpoint = "none";
            setuid = "off";
            xattr = "sa";
          };
      message = "tank must remain a two-member mirror with conservative creation and inherited root properties";
    }
    {
      assertion = builtins.attrNames tank.datasets == expectedDatasets;
      message = "tank must contain exactly the explicit owner, protected, and disposable dataset tree";
    }
    {
      assertion =
        policy.ownerQuotaBytes == 220000000000
        && policy.ownerWarningBytes == 180000000000
        && tank.datasets."users/alex".options.quota == "220000000000"
        && tank.datasets."users/andreea".options.quota == "220000000000"
        && !(tank.datasets."users/alex".options ? refquota)
        && !(tank.datasets."users/andreea".options ? refquota);
      message = "each owner parent must carry the exact unsuffixed decimal quota, never a refquota";
    }
    {
      assertion = lib.all (
        name:
        tank.datasets.${name}.mountpoint == null
        && tank.datasets.${name}.options.mountpoint == "none"
        && tank.datasets.${name}.options.canmount == "off"
      ) structuralDatasets;
      message = "owner and hierarchy parents must be explicit non-mountable, non-writable structural datasets";
    }
    {
      assertion = lib.all (
        mountpoint:
        let
          fs = config.fileSystems.${mountpoint};
        in
        fs.device == expectedMounts.${mountpoint}
        && fs.fsType == "zfs"
        && builtins.elem "zfsutil" fs.options
        && !builtins.elem "nofail" fs.options
      ) (builtins.attrNames expectedMounts);
      message = "every protected/disposable leaf must be a mandatory ZFS mount at its declared host path";
    }
    {
      assertion = lib.all (
        name:
        let
          leaf = tank.datasets.${name};
        in
        leaf.options.canmount == "noauto"
        && leaf.options.devices == "off"
        && leaf.options.setuid == "off"
        && leaf.options.exec == (if lib.hasSuffix "/home" name then "on" else "off")
      ) leafDatasets;
      message = "leaf execution, device, and setuid properties must be explicit and safe for their use";
    }
    {
      assertion =
        policy.protectedLeafDatasets == expectedProtected
        && policy.disposableDatasets == expectedDisposable
        && lib.intersectLists policy.protectedLeafDatasets policy.disposableDatasets == [ ]
        && lib.all (name: builtins.elem (lib.removePrefix "tank/" name) leafDatasets) (
          policy.protectedLeafDatasets ++ policy.disposableDatasets
        );
      message = "the typed protected allowlist and disposable list must be explicit, complete, and disjoint";
    }
    {
      assertion =
        builtins.filter (lib.hasPrefix "zfs.zfs_arc_max=") config.boot.kernelParams == [
          "zfs.zfs_arc_max=8589934592"
        ];
      message = "OpenZFS ARC must be capped at exactly 8 GiB through its kernel module parameter";
    }
    {
      assertion =
        config.fileSystems."/".device == "/dev/md/root"
        && config.fileSystems."/".fsType == "ext4"
        && config.fileSystems."/boot".device == "/dev/disk/by-partlabel/disk-crucial-ESP"
        && config.fileSystems."/boot".fsType == "vfat"
        && config.fileSystems."/boot-fallback".device == "/dev/disk/by-partlabel/disk-kingston-ESP"
        && config.fileSystems."/boot-fallback".fsType == "vfat";
      message = "disko must retain md root and both independent ESP runtime mounts";
    }
    {
      assertion =
        config.networking.hostId == "8bdbe130"
        && config.boot.swraid.enable
        && config.boot.initrd.supportedFilesystems.zfs
        && config.boot.supportedFilesystems.zfs
        && config.boot.zfs.extraPools == [ "tank" ]
        && config.boot.zfs.devNodes == "/dev/disk/by-partlabel"
        && !config.boot.zfs.forceImportRoot
        && !config.boot.zfs.forceImportAll
        && !config.boot.zfs.requestEncryptionCredentials;
      message = "stable host identity and conservative md/ZFS initrd/import settings must remain enabled";
    }
    {
      assertion =
        map (boot: {
          inherit (boot) path devices;
        }) grubBoots == [
          {
            path = "/boot";
            devices = [ expectedDevices.crucial ];
          }
          {
            path = "/boot-fallback";
            devices = [ expectedDevices.kingston ];
          }
        ];
      message = "GRUB must install independently to the matching physical device for each ESP";
    }
    {
      assertion = lib.all (mount: !builtins.hasAttr mount config.fileSystems) obsoleteMounts;
      message = "legacy ext4 data mounts must remain absent";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur storage invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-storage-tests" { } ''
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} storage invariants passed.' > "$out/result"
  ''
