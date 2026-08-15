{
  defaultConfig,
  readyConfig,
  pkgs,
  llamaPackage,
}:

let
  inherit (pkgs) lib;
  ready = readyConfig.balaur.sharedServices.llama;
  unit = readyConfig.systemd.services.llama-router;
  expectedArgs = [
    "${llamaPackage}/bin/llama-server"
    "--host"
    "127.0.0.1"
    "--port"
    "8081"
    "--offline"
    "--models-preset"
    "/srv/models/approved/router.ini"
    "--models-max"
    "1"
    "--models-autoload"
    "--parallel"
    "1"
    "--ctx-size"
    "32768"
    "--cache-type-k"
    "f16"
    "--cache-type-v"
    "f16"
    "--n-gpu-layers"
    "all"
    "--fit"
    "off"
    "--cache-prompt"
    "--metrics"
    "--no-slots"
    "--no-ui"
    "--log-disable"
    "--sleep-idle-seconds"
    "1800"
    "--api-key-file"
    "/run/llama-router/api-keys"
  ];
  firewallPorts =
    readyConfig.networking.firewall.allowedTCPPorts
    ++ readyConfig.networking.firewall.allowedUDPPorts
    ++ lib.concatMap (
      interface:
      readyConfig.networking.firewall.interfaces.${interface}.allowedTCPPorts
      ++ readyConfig.networking.firewall.interfaces.${interface}.allowedUDPPorts
    ) readyConfig.balaur.network.trustedInterfaces;
  assertions = [
    {
      assertion =
        !defaultConfig.balaur.sharedServices.llama.readiness.ready
        && defaultConfig.balaur.sharedServices.llama.readiness.modelPresetFile == null
        && defaultConfig.balaur.sharedServices.llama.readiness.ownerApiKeyFiles.alex == null
        && defaultConfig.balaur.sharedServices.llama.readiness.ownerApiKeyFiles.andreea == null
        && defaultConfig.balaur.sharedServices.llama.readiness.memoryHighBytes == null
        && !(defaultConfig.systemd.services ? llama-router)
        && !(defaultConfig.users.users ? llama)
        && lib.any (warning: lib.hasInfix "llama.cpp is disabled" warning) defaultConfig.warnings;
      message = "the production llama service must be absent by default without reading missing runtime files";
    }
    {
      assertion =
        ready.readiness.ready
        && ready.readiness.modelPresetFile == "/srv/models/approved/router.ini"
        &&
          ready.readiness.ownerApiKeyFiles == {
            alex = "/run/balaur-secrets/owners/alex/llama/api-key";
            andreea = "/run/balaur-secrets/owners/andreea/llama/api-key";
          }
        && ready.readiness.memoryHighBytes == 34359738368;
      message = "the ready interface must require one models preset, distinct owner-policy keys, and benchmark-derived memory protection";
    }
    {
      assertion =
        unit.serviceConfig.ExecStart == lib.escapeShellArgs expectedArgs
        && unit.environment.GGML_CUDA_ENABLE_UNIFIED_MEMORY == "1"
        && unit.environment.LLAMA_OFFLINE == "1"
        && unit.environment.LLAMA_CACHE == "/srv/models/.llama-router-disabled-cache";
      message = "router, offline, UMA, lazy loading, one-slot, context, F16 KV, full-offload, metrics, no-log, and idle flags must remain exact";
    }
    {
      assertion =
        unit.unitConfig.RequiresMountsFor == [ "/srv/models" ]
        && unit.unitConfig.ConditionPathIsMountPoint == [ "/srv/models" ]
        && builtins.elem "local-fs.target" unit.requires
        && builtins.elem "local-fs.target" unit.after
        && builtins.elem "/srv/models" unit.serviceConfig.ReadOnlyPaths;
      message = "llama must fail closed on the disposable models mount and never prepare fallback state on md root";
    }
    {
      assertion =
        unit.serviceConfig.LoadCredential == [
          "alex-api-key:/run/balaur-secrets/owners/alex/llama/api-key"
          "andreea-api-key:/run/balaur-secrets/owners/andreea/llama/api-key"
        ]
        && lib.hasInfix "CREDENTIALS_DIRECTORY" unit.preStart
        && lib.hasInfix "sort -u" unit.preStart
        && !lib.hasInfix "api-key " unit.serviceConfig.ExecStart;
      message = "b9190 multi-key authentication must combine distinct runtime credentials without putting key values on the command line or in the store";
    }
    {
      assertion =
        unit.serviceConfig.CPUWeight == 100
        && unit.serviceConfig.IOWeight == 100
        && unit.serviceConfig.IOSchedulingPriority == 4
        && unit.serviceConfig.CPUWeight < readyConfig.systemd.services.jellyfin.serviceConfig.CPUWeight
        && unit.serviceConfig.IOWeight < readyConfig.systemd.services.jellyfin.serviceConfig.IOWeight
        && unit.serviceConfig.MemoryHigh == "34359738368"
        && !(unit.serviceConfig ? MemoryLow)
        && !(unit.serviceConfig ? MemoryMax)
        && unit.serviceConfig.ManagedOOMMemoryPressure == "kill"
        && unit.serviceConfig.OOMScoreAdjust == 500;
      message = "optional inference must rank below Jellyfin and use benchmark-derived MemoryHigh without MemoryLow protection or an unproven hard maximum";
    }
    {
      assertion =
        unit.serviceConfig.PrivateDevices
        && builtins.elem "/dev/kfd rw" unit.serviceConfig.DeviceAllow
        && builtins.elem "/dev/dri/renderD128 rw" unit.serviceConfig.DeviceAllow
        && builtins.elem "render" readyConfig.users.users.llama.extraGroups
        && builtins.elem "video" readyConfig.users.users.llama.extraGroups
        && unit.serviceConfig.IPAddressDeny == "any"
        && builtins.elem "127.0.0.0/8" unit.serviceConfig.IPAddressAllow;
      message = "GPU device access and loopback-only network confinement must be explicit";
    }
    {
      assertion =
        !builtins.elem 8081 firewallPorts
        && !(readyConfig.balaur.ingress.reverseProxies ? "chat.alex.home.arpa")
        && !(readyConfig.balaur.ingress.reverseProxies ? "chat.andreea.home.arpa");
      message = "the raw backend must have no LAN or Caddy ingress";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur llama service invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-llama-service-tests" { } ''
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} llama service invariants passed.' > "$out/result"
  ''
