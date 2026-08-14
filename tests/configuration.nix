{ config, pkgs }:

let
  inherit (pkgs) lib;
  packageNames = map lib.getName config.environment.systemPackages;
  serviceNames = builtins.attrNames config.systemd.services;
  forbiddenServices = [
    "fastflowlm"
    "web-desktop-vnc"
    "web-desktop-novnc"
    "web-desktop-session"
    "balaur-dashboard"
    "herdr-web"
  ];
  assertions = [
    {
      assertion = config.networking.hostName == "balaur" && config.system.stateVersion == "26.05";
      message = "host identity and state version must remain stable";
    }
    {
      assertion =
        config.nixpkgs.hostPlatform.system == "x86_64-linux"
        && config.networking.hostId == "8bdbe130"
        &&
          map (boot: boot.path) config.boot.loader.grub.mirroredBoots == [
            "/boot"
            "/boot-fallback"
          ]
        && config.fileSystems."/".device == "/dev/md/root";
      message = "the target platform, stable host identity, disko root, and mirrored GRUB must remain evaluable";
    }
    {
      assertion =
        !config.services.xserver.enable
        && lib.all (service: !builtins.elem service serviceNames) forbiddenServices
        && !builtins.elem "amdxdna" config.boot.kernelModules
        && !(config.users.users ? fastflowlm)
        && lib.all (name: !builtins.elem name packageNames) [
          "chromium"
          "fastflowlm"
          "herdr"
        ];
      message = "the baseline must exclude desktop, VNC, dashboard, Herdr, and FastFlowLM/XDNA";
    }
    {
      assertion =
        builtins.elem "pi-coding-agent" packageNames
        && lib.any (lib.hasInfix "/extensions/pi-subagents") config.systemd.tmpfiles.rules
        && lib.any (lib.hasInfix "/extensions/pi-web-access") config.systemd.tmpfiles.rules
        && lib.all (rule: !lib.hasInfix "models.json" rule) config.systemd.tmpfiles.rules;
      message = "pi and its local extensions must remain installed without an obsolete Qwen model provider";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur global invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-configuration-tests" { } ''
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} global invariants passed.' > "$out/result"
  ''
