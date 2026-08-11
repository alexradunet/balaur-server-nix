{
  autoPatchelfHook,
  curl,
  fetchurl,
  lib,
  stdenv,
  util-linux,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "fastflowlm";
  version = "1.0.0";

  src = fetchurl {
    url = "https://github.com/ROCm/FastFlowLM/releases/download/v${finalAttrs.version}/fastflowlm_${finalAttrs.version}_linux.tar.gz";
    hash = "sha256-7sndCglBqZeCk38YwIY51qOIHGdYZk2+ZjKg5wAAHhM=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    curl
    stdenv.cc.cc.lib
    util-linux.lib
  ];

  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 flm "$out/libexec/fastflowlm/flm"
    install -Dm755 flm-real "$out/libexec/fastflowlm/flm-real"
    cp -a lib model_info.json model_list.json "$out/libexec/fastflowlm/"
    # Software-emulation plugins are not used for the physical XDNA NPU and
    # require an otherwise-unneeded, ABI-pinned protobuf runtime.
    rm -f "$out/libexec/fastflowlm/lib/"libxrt_{hwemu,swemu}.so*
    rm -f "$out/libexec/fastflowlm/lib/x86_64-linux-gnu/"libxrt_{hwemu,swemu}.so*

    substituteInPlace "$out/libexec/fastflowlm/flm" \
      --replace-fail '#!/bin/bash' '#!${stdenv.shell}'

    mkdir -p "$out/bin"
    cat > "$out/bin/flm" <<EOF
    #!${stdenv.shell}
    exec "$out/libexec/fastflowlm/flm" "\$@"
    EOF
    chmod 0755 "$out/bin/flm"

    runHook postInstall
  '';

  meta = {
    description = "NPU-first LLM runtime for AMD Ryzen AI XDNA2 NPUs";
    homepage = "https://github.com/ROCm/FastFlowLM";
    license = lib.licenses.unfreeRedistributable;
    mainProgram = "flm";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
