{ lib, ... }:

{
  # The pinned disko install test provides two disposable 4 GiB virtio disks.
  # Scale only partition capacities to fit that harness; topology, filesystems,
  # UEFI mounts, md RAID1, and the ZFS mirror remain identical to the host.
  disko.devices.disk = {
    crucial.content.partitions = {
      ESP.size = lib.mkForce "256M";
      root.size = lib.mkForce "1G";
      tank.end = lib.mkForce "-256M";
    };
    kingston.content.partitions = {
      ESP.size = lib.mkForce "256M";
      root.size = lib.mkForce "1G";
      tank.end = lib.mkForce "-256M";
    };
  };

  # Disko rewrites layout devices to disposable virtio disks. EFI GRUB needs no
  # physical device argument in the VM, but still writes both mounted ESPs.
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  boot.zfs.devNodes = lib.mkForce "/dev";
  boot.loader.grub.devices = lib.mkForce [ ];
  boot.loader.grub.mirroredBoots = lib.mkForce [
    {
      path = "/boot";
      devices = [ "nodev" ];
    }
    {
      path = "/boot-fallback";
      devices = [ "nodev" ];
    }
  ];

  disko.tests.extraChecks = ''
    machine.succeed("mountpoint /")
    machine.succeed("mountpoint /boot")
    machine.succeed("mountpoint /boot-fallback")
    machine.succeed("mdadm --detail /dev/md/root | grep -F 'Raid Level : raid1'")
    machine.succeed("zpool status tank | grep -F 'mirror-0'")
    machine.succeed("test -e /boot/EFI/BOOT/BOOTX64.EFI")
    machine.succeed("test -e /boot-fallback/EFI/BOOT/BOOTX64.EFI")

    machine.succeed("test \"$(zfs list -H -o name | sort | tr '\\n' ' ')\" = \"tank tank/disposable tank/disposable/cache tank/disposable/downloads tank/disposable/media tank/disposable/models tank/disposable/temp tank/services tank/shared tank/users tank/users/alex tank/users/alex/apps tank/users/alex/home tank/users/andreea tank/users/andreea/apps tank/users/andreea/home \"")
    machine.succeed("test \"$(zpool get -H -p -o value ashift tank)\" = 12")
    machine.succeed("for property_value in compression:lz4 checksum:on xattr:sa acltype:posix atime:off devices:off setuid:off canmount:off mountpoint:none; do property=''${property_value%:*}; value=''${property_value#*:}; test \"$(zfs get -H -p -o value \"$property\" tank)\" = \"$value\"; done")

    machine.succeed("for owner in alex andreea; do test \"$(zfs get -H -p -o value quota tank/users/$owner)\" = 220000000000; test \"$(zfs get -H -o value canmount tank/users/$owner)\" = off; test \"$(zfs get -H -o value mountpoint tank/users/$owner)\" = none; test \"$(zfs get -H -o value mounted tank/users/$owner)\" = no; done")
    machine.succeed("for parent in tank/users tank/disposable; do test \"$(zfs get -H -o value canmount $parent)\" = off; test \"$(zfs get -H -o value mountpoint $parent)\" = none; test \"$(zfs get -H -o value mounted $parent)\" = no; done")

    machine.succeed("while read -r dataset path; do mountpoint \"$path\"; test \"$(findmnt -n -o SOURCE --target \"$path\")\" = \"$dataset\"; test \"$(zfs get -H -o value mountpoint \"$dataset\")\" = \"$path\"; done <<'EOF'\ntank/users/alex/home /home/alex\ntank/users/alex/apps /srv/people/alex/apps\ntank/users/andreea/home /home/andreea\ntank/users/andreea/apps /srv/people/andreea/apps\ntank/shared /srv/shared\ntank/services /srv/services\ntank/disposable/media /srv/media\ntank/disposable/downloads /srv/downloads\ntank/disposable/models /srv/models\ntank/disposable/cache /srv/cache\ntank/disposable/temp /srv/temp\nEOF")
    machine.succeed("for dataset in tank/users/alex/home tank/users/andreea/home; do test \"$(zfs get -H -o value exec $dataset)\" = on; test \"$(zfs get -H -o value canmount $dataset)\" = noauto; done")
    machine.succeed("for dataset in tank/users/alex/apps tank/users/andreea/apps tank/shared tank/services tank/disposable/media tank/disposable/downloads tank/disposable/models tank/disposable/cache tank/disposable/temp; do test \"$(zfs get -H -o value exec $dataset)\" = off; test \"$(zfs get -H -o value canmount $dataset)\" = noauto; test \"$(zfs get -H -o value devices $dataset)\" = off; test \"$(zfs get -H -o value setuid $dataset)\" = off; done")
    machine.succeed("systemctl is-active zfs-mount.service")
    machine.succeed("test \"$(stat -c '%U:%G:%a' /home/alex)\" = alex:users:700")
    machine.succeed("su -s /bin/sh alex -c 'touch /home/alex/.storage-write-test && rm /home/alex/.storage-write-test'")
    machine.succeed("test \"$(cat /sys/module/zfs/parameters/zfs_arc_max)\" = 8589934592")
  '';
}
