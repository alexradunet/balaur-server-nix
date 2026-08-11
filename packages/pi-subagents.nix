{
  buildNpmPackage,
  fetchFromGitHub,
  lib,
  nodejs,
}:

buildNpmPackage rec {
  pname = "pi-subagents";
  version = "0.14.3";

  src = fetchFromGitHub {
    owner = "tintinweb";
    repo = "pi-subagents";
    rev = "v${version}";
    hash = "sha256-ZztgK9TUrpLsTSmYTOlHu8f6P5G/EA3MmVhqSfFZLQA=";
  };

  npmDepsHash = "sha256-UgZg6EWSuiQQCR+kwYBnQ+Hen08PwIsz84+o7e3yvrY=";

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

  # Pi otherwise labels this extension "src" because the upstream manifest
  # points at src/index.ts. A top-level entry point gives it the package name.
  postInstall = ''
    packageDir="$out/lib/node_modules/@tintinweb/pi-subagents"
    cat > "$packageDir/index.ts" <<'EOF'
    export { default } from "./src/index.ts";
    EOF

    ${nodejs}/bin/node - "$packageDir/package.json" <<'EOF'
    const fs = require("fs");
    const path = process.argv[2];
    const packageJson = JSON.parse(fs.readFileSync(path, "utf8"));
    packageJson.pi.extensions = ["./index.ts"];
    fs.writeFileSync(path, JSON.stringify(packageJson, null, 2) + "\n");
    EOF
  '';

  meta = {
    description = "Autonomous sub-agents extension for Pi";
    homepage = "https://github.com/tintinweb/pi-subagents";
    license = lib.licenses.mit;
  };
}
