{
  config,
  lib,
  ...
}:

let
  cfg = config.balaur.storage;

  protectedLeaves = [
    {
      dataset = "tank/users/alex/home";
      mountpoint = "/home/alex";
      exec = "on";
    }
    {
      dataset = "tank/users/alex/apps";
      mountpoint = "/srv/people/alex/apps";
      exec = "off";
    }
    {
      dataset = "tank/users/andreea/home";
      mountpoint = "/home/andreea";
      exec = "on";
    }
    {
      dataset = "tank/users/andreea/apps";
      mountpoint = "/srv/people/andreea/apps";
      exec = "off";
    }
    {
      dataset = "tank/shared";
      mountpoint = "/srv/shared";
      exec = "off";
    }
    {
      dataset = "tank/services";
      mountpoint = "/srv/services";
      exec = "off";
    }
  ];

  disposableLeaves = [
    {
      dataset = "tank/disposable/media";
      mountpoint = "/srv/media";
    }
    {
      dataset = "tank/disposable/downloads";
      mountpoint = "/srv/downloads";
    }
    {
      dataset = "tank/disposable/models";
      mountpoint = "/srv/models";
    }
    {
      dataset = "tank/disposable/cache";
      mountpoint = "/srv/cache";
    }
    {
      dataset = "tank/disposable/temp";
      mountpoint = "/srv/temp";
    }
  ];

  relativeName = lib.removePrefix "tank/";
  mkLeaf = leaf: {
    name = relativeName leaf.dataset;
    value = {
      type = "zfs_fs";
      inherit (leaf) mountpoint;
      options = {
        # Explicit systemd mount units own ordering and failure handling. noauto
        # prevents zfs-mount.service from racing those mandatory mounts.
        canmount = "noauto";
        exec = leaf.exec or "off";
        devices = "off";
        setuid = "off";
      };
    };
  };

  ownerParent = owner: {
    name = "users/${owner}";
    value = {
      type = "zfs_fs";
      options = {
        mountpoint = "none";
        canmount = "off";
        quota = toString cfg.ownerQuotaBytes;
        exec = "off";
        devices = "off";
        setuid = "off";
      };
    };
  };
in
{
  options.balaur.storage = {
    ownerQuotaBytes = lib.mkOption {
      type = lib.types.ints.positive;
      readOnly = true;
      default = 220000000000;
      description = "Exact decimal-byte quota applied to each owner parent dataset.";
    };

    ownerWarningBytes = lib.mkOption {
      type = lib.types.ints.positive;
      readOnly = true;
      default = 180000000000;
      description = "Exact decimal-byte owner usage threshold consumed by later monitoring policy.";
    };

    protectedLeafDatasets = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "^tank/.+");
      readOnly = true;
      default = map (leaf: leaf.dataset) protectedLeaves;
      description = "Explicit non-recursive allowlist for later snapshots and backups.";
    };

    disposableDatasets = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "^tank/disposable/.+");
      readOnly = true;
      default = map (leaf: leaf.dataset) disposableLeaves;
      description = "Explicit datasets excluded from snapshots and backups by later policy.";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.ownerWarningBytes < cfg.ownerQuotaBytes;
        message = "the owner storage warning must remain below the owner quota";
      }
      {
        assertion = lib.intersectLists cfg.protectedLeafDatasets cfg.disposableDatasets == [ ];
        message = "protected and disposable ZFS dataset lists must remain disjoint";
      }
    ];

    disko.devices.zpool.tank = {
      # ashift is fixed at pool creation. 4 KiB sectors are the conservative
      # choice for both current NVMe devices and likely replacement media.
      options.ashift = "12";

      # Keep the pool root and all structural datasets unmounted. Leaf datasets
      # below receive explicit mountpoints and inherit these low-risk defaults.
      rootFsOptions = {
        mountpoint = "none";
        canmount = "off";
        compression = "lz4";
        checksum = "on";
        xattr = "sa";
        acltype = "posixacl";
        atime = "off";
        devices = "off";
        setuid = "off";
      };

      datasets = builtins.listToAttrs (
        [
          {
            name = "users";
            value = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                canmount = "off";
                exec = "off";
                devices = "off";
                setuid = "off";
              };
            };
          }
          (ownerParent "alex")
          (ownerParent "andreea")
          {
            name = "disposable";
            value = {
              type = "zfs_fs";
              options = {
                mountpoint = "none";
                canmount = "off";
                exec = "off";
                devices = "off";
                setuid = "off";
              };
            };
          }
        ]
        ++ map mkLeaf protectedLeaves
        ++ map mkLeaf disposableLeaves
      );
    };

    # OpenZFS reads this module parameter when NixOS loads zfs in the initrd.
    # The unsuffixed value is exactly 8 * 1024^3 bytes.
    boot.kernelParams = [ "zfs.zfs_arc_max=8589934592" ];

    # Issue 07 creates Andreea and owns her mounts. Only paths whose owner
    # already exists are adjusted here, after local ZFS mounts are available.
    systemd.tmpfiles.rules = [
      "d /home/alex 0700 alex users -"
      "d /srv/people/alex/apps 0700 alex users -"
    ];
  };
}
