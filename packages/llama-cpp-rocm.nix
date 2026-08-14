{ pkgs }:

let
  llama = pkgs.llama-cpp.override {
    rocmSupport = true;
    rocmGpuTargets = [ "gfx1150" ];
  };
  requiredFlags = [
    "-DGGML_HIP:BOOL=TRUE"
    "-DCMAKE_HIP_ARCHITECTURES:STRING=gfx1150"
  ];
  rocmVersions = map (package: package.version) [
    pkgs.rocmPackages.clr
    pkgs.rocmPackages.hipblas
    pkgs.rocmPackages.rocblas
  ];
in
assert llama.version == "9190";
assert pkgs.lib.all (flag: builtins.elem flag llama.cmakeFlags) requiredFlags;
assert pkgs.lib.all (version: version == "7.2.3") rocmVersions;
llama.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    balaurRocmBuild = {
      llamaVersion = "9190";
      rocmVersion = "7.2.3";
      gpuTargets = [ "gfx1150" ];
      cmakeFlags = requiredFlags;
      # llama.cpp b9190 implements HIP UMA at runtime, not as a CMake option.
      # modules/llama.nix supplies this exact upstream setting to the service.
      unifiedMemoryEnvironment = "GGML_CUDA_ENABLE_UNIFIED_MEMORY=1";
    };
  };
})
