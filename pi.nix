{
  buildFHSEnv,
  fetchurl,
  stdenvNoCC,
}:

let
  piFiles = stdenvNoCC.mkDerivation {
    pname = "pi-coding-agent-files";
    version = "0.84.1";

    src = fetchurl {
      url = "https://github.com/earendil-works/pi/releases/download/v0.84.1/pi-linux-x64.tar.gz";
      hash = "sha256-VjTX69GCdLY68zcelC80LXS+oBI4lXXB0f8VzmyoDC8=";
    };

    sourceRoot = "pi";

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/pi"
      cp -r . "$out/lib/pi"
      runHook postInstall
    '';
  };
in
buildFHSEnv {
  name = "pi";
  runScript = "${piFiles}/lib/pi/pi";
}
