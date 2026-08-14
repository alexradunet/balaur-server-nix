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
    machine.succeed("test $(zfs list -H -o name | wc -l) -eq 1")
  '';
}
