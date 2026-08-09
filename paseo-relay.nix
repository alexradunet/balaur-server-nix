{ beam29Packages, lib, src }:

beam29Packages.mixRelease rec {
  pname = "paseo-relay";
  version = "0.1.0-unstable-2026-08-05";

  inherit src;

  elixir = beam29Packages.elixir_1_20;
  erlang = beam29Packages.erlang;

  mixFodDeps = beam29Packages.fetchMixDeps {
    pname = "mix-deps-${pname}";
    inherit src version;
    hash = "sha256-3J2C4XGqjdM0TYf+Vkv5/AY59tiKLVX81Gxrs9pvKuY=";
  };

  mixReleaseName = "paseo_relay";
  removeCookie = false;

  meta = {
    description = "Distributed, protocol-compatible relay for Paseo";
    homepage = "https://github.com/getpaseo/paseo-relay";
    license = lib.licenses.asl20;
    mainProgram = "paseo_relay";
    platforms = lib.platforms.linux;
  };
}
