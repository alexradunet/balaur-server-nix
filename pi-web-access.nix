{
  buildNpmPackage,
  fetchFromGitHub,
  lib,
  nodejs,
}:

buildNpmPackage rec {
  pname = "pi-web-access";
  version = "0.20.0";

  src = fetchFromGitHub {
    owner = "nicobailon";
    repo = "pi-web-access";
    rev = "v${version}";
    hash = "sha256-swxpJ3c1LIWgiKWSmP7AyKSUGO64nXKHHBd12484pIg=";
  };

  npmDepsHash = "sha256-Kp16OONnaQtIzAYdEpAfbSHzZ1bYvL07Qcl0z9pUx3I=";

  # Pi provides these packages to extensions. Removing them from the lock file
  # also avoids installing a second copy of Pi through npm peer resolution.
  postPatch = ''
    ${nodejs}/bin/node <<'EOF'
    const fs = require("fs");

    const packageJson = JSON.parse(fs.readFileSync("package.json", "utf8"));
    delete packageJson.peerDependencies;
    fs.writeFileSync("package.json", `''${JSON.stringify(packageJson, null, 2)}\n`);

    const packageLock = JSON.parse(fs.readFileSync("package-lock.json", "utf8"));
    delete packageLock.packages[""].peerDependencies;
    for (const [path, entry] of Object.entries(packageLock.packages)) {
      if (entry.peer) delete packageLock.packages[path];
    }
    fs.writeFileSync("package-lock.json", `''${JSON.stringify(packageLock, null, 2)}\n`);
    EOF
  '';

  dontNpmBuild = true;
  npmInstallFlags = [
    "--omit=dev"
    "--omit=peer"
  ];

  meta = {
    description = "Web search and content extraction extension for Pi";
    homepage = "https://github.com/nicobailon/pi-web-access";
    license = lib.licenses.mit;
  };
}
