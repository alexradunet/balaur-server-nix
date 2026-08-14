{ config, pkgs }:

let
  inherit (pkgs) lib;
  devices = config.disko.devices;
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
        && devices.zpool.tank.mode == "mirror"
        && devices.zpool.tank.options == { }
        && devices.zpool.tank.rootFsOptions == { }
        && builtins.attrNames devices.zpool.tank.datasets == [ "__root" ];
      message = "tank must be a property-minimal two-member mirror without issue-06 datasets";
    }
    {
      assertion =
        builtins.attrNames config.fileSystems == [
          "/"
          "/boot"
          "/boot-fallback"
        ]
        && config.fileSystems."/".device == "/dev/md/root"
        && config.fileSystems."/".fsType == "ext4"
        && config.fileSystems."/boot".device == "/dev/disk/by-partlabel/disk-crucial-ESP"
        && config.fileSystems."/boot".fsType == "vfat"
        && config.fileSystems."/boot-fallback".device == "/dev/disk/by-partlabel/disk-kingston-ESP"
        && config.fileSystems."/boot-fallback".fsType == "vfat";
      message = "disko alone must own root and both independent ESP runtime mount declarations";
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
      message = "legacy mounts and issue-06 dataset mounts must remain absent";
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
