{ config, pkgs }:

let
  inherit (pkgs) lib;
  obsoleteMounts = [
    "/srv/app-data"
    "/srv/personal"
    "/srv/media/ssd0"
    "/srv/media/ssd1"
  ];
  assertions = [
    {
      assertion =
        config.boot.kernelPackages.kernel.version == pkgs.linuxPackages_6_18.kernel.version
        && config.boot.zfs.package.version == pkgs.zfs_2_4.version;
      message = "Linux 6.18 and OpenZFS 2.4 must be the explicit target compatibility pair";
    }
    {
      assertion = lib.all (mount: !builtins.hasAttr mount config.fileSystems) obsoleteMounts;
      message = "legacy application and media mounts must remain absent";
    }
    {
      assertion =
        !(config.fileSystems ? "/tank")
        && !(config.fileSystems ? "/home/alex/files")
        && !(config.fileSystems ? "/home/andreea/files");
      message = "physical ZFS pool and dataset mounts belong to issues 05 and 06";
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
    printf '%s\n' 'Storage baseline invariants passed.' > "$out/result"
  ''
