{ pkgs, llamaPackage }:

let
  inherit (pkgs) lib;
  build = llamaPackage.passthru.balaurRocmBuild;
  hipArchitectureFlags = builtins.filter (
    flag: lib.hasPrefix "-DCMAKE_HIP_ARCHITECTURES:" flag
  ) llamaPackage.cmakeFlags;
  assertions = [
    {
      assertion = llamaPackage.version == "9190" && build.llamaVersion == "9190";
      message = "llama.cpp must remain pinned to nixpkgs build 9190";
    }
    {
      assertion =
        builtins.elem "-DGGML_HIP:BOOL=TRUE" llamaPackage.cmakeFlags
        && hipArchitectureFlags == [ "-DCMAKE_HIP_ARCHITECTURES:STRING=gfx1150" ]
        && build.gpuTargets == [ "gfx1150" ];
      message = "the llama derivation must enable HIP for only gfx1150";
    }
    {
      assertion =
        pkgs.rocmPackages.clr.version == "7.2.3"
        && pkgs.rocmPackages.hipblas.version == "7.2.3"
        && pkgs.rocmPackages.rocblas.version == "7.2.3"
        && build.rocmVersion == "7.2.3";
      message = "the llama HIP closure must use pinned ROCm 7.2.3 components";
    }
    {
      assertion = build.unifiedMemoryEnvironment == "GGML_CUDA_ENABLE_UNIFIED_MEMORY=1";
      message = "the package contract must record b9190's verified HIP UMA runtime setting";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur llama package invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-llama-package-tests" { nativeBuildInputs = [ llamaPackage ]; } ''
    set -eu
    llama-server --version 2>&1 | grep -F 'version: 9190'
    test -e ${llamaPackage}/lib/libggml-hip.so
    mkdir -p "$out"
    printf '%s\n' 'llama.cpp 9190 ROCm closure and executable verified; no GPU runtime claim.' > "$out/result"
  ''
