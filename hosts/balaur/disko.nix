{ ... }:

let
  # These are the two observed wipe targets. Changing either path changes which
  # physical device disko will destroy.
  crucial = "/dev/disk/by-id/nvme-CT1000P3PSSD8_24454C2CAAFE";
  kingston = "/dev/disk/by-id/nvme-KINGSTON_SNV3S1000G_50026B76870B8ECD";

  diskLayout = device: espMountpoint: {
    type = "disk";
    inherit device;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 100;
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = espMountpoint;
            mountOptions = [
              "fmask=0022"
              "dmask=0022"
            ];
          };
        };
        root = {
          priority = 200;
          size = "128G";
          type = "FD00";
          content = {
            type = "mdraid";
            name = "root";
          };
        };
        tank = {
          priority = 300;
          size = "100%";
          # disko passes this to sgdisk. G is binary GiB: 4,294,967,296
          # bytes of tail slack, comfortably above the observed devices'
          # 204,886,016-byte margin over decimal 1 TB.
          end = "-4G";
          type = "BF01";
          content = {
            type = "zfs";
            pool = "tank";
          };
        };
      };
    };
  };
in
{
  # DANGER: disko's destroy/format scripts wipe both devices above and recreate
  # this complete layout. They must not be run on the physical host before the
  # typed serial confirmation and other gates in issue 16.
  disko = {
    checkScripts = true;
    devices = {
      disk = {
        crucial = diskLayout crucial "/boot";
        kingston = diskLayout kingston "/boot-fallback";
      };

      mdadm.root = {
        type = "mdadm";
        level = 1;
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/";
        };
      };

      zpool.tank = {
        type = "zpool";
        mode = "mirror";
        # Issue 06 owns all named datasets, quotas, and data-policy properties.
        datasets = { };
      };
    };
  };
}
