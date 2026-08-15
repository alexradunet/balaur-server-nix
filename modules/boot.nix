{ ... }:

{
  # ------------------------------------------------------------
  # Boot
  # ------------------------------------------------------------

  boot.loader.systemd-boot.enable = false;

  boot.loader.efi.canTouchEfiVariables = true;

  # Root is assembled in stage 1. Disko also enables swraid from the md device,
  # but keeping this explicit makes the boot requirement visible here.
  boot.swraid.enable = true;

  # ZFS support is available in the initrd for recovery, while the data-only
  # tank pool is imported normally in stage 2. Forced imports stay disabled.
  boot.initrd.supportedFilesystems = [ "zfs" ];
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs = {
    devNodes = "/dev/disk/by-partlabel";
    extraPools = [ "tank" ];
    forceImportRoot = false;
    forceImportAll = false;
    requestEncryptionCredentials = false;
  };

  boot.loader.grub = {
    enable = true;
    efiSupport = true;

    # Keep a complete bootloader on both NVMe EFI partitions.
    mirroredBoots = [
      {
        path = "/boot";
        devices = [ "/dev/disk/by-id/nvme-CT1000P3PSSD8_24454C2CAAFE" ];
      }
      {
        path = "/boot-fallback";
        devices = [ "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B76870B8ECD" ];
      }
    ];
  };
}
