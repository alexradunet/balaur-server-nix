{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.balaur.sharedServices.llama;
  ownerSecretRoot = owner: config.balaur.secrets.policies.${owner}.runtimeDirectory;
  llamaPackage = pkgs.callPackage ../packages/llama-cpp-rocm.nix { };
  runtimeDirectory = "/run/llama-router";
  apiKeyFile = "${runtimeDirectory}/api-keys";
  serverArgs = [
    "${cfg.package}/bin/llama-server"
    "--host"
    cfg.backend.host
    "--port"
    (toString cfg.backend.port)
    "--offline"
    "--models-preset"
    cfg.readiness.modelPresetFile
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
    apiKeyFile
  ];
  validatePreset = pkgs.writeShellScript "validate-llama-model-preset" ''
    set -eu
    preset="$1"
    test -f "$preset"

    # Router presets are deliberately local-only. b9190 also receives
    # --offline and a loopback-only systemd network policy, but reject network
    # model sources here rather than relying on either fallback.
    if ${pkgs.gnugrep}/bin/grep -Eiq '(^|[[:space:]])(hf-repo|hf-file|model-url|docker-repo)[[:space:]]*=|https?://' "$preset"; then
      echo "llama preset contains a forbidden network model source" >&2
      exit 1
    fi
    if ${pkgs.gnugrep}/bin/grep -Eiq '^[[:space:]]*load-on-startup[[:space:]]*=[[:space:]]*(1|true|yes|on)[[:space:]]*$' "$preset"; then
      echo "llama preset must remain lazy at startup" >&2
      exit 1
    fi
    if ${pkgs.gnugrep}/bin/grep -Ev '^[[:space:]]*($|[;#].*|version[[:space:]]*=[[:space:]]*1|\[[A-Za-z0-9._:-]+\]|model[[:space:]]*=[[:space:]]*/srv/models/[A-Za-z0-9._/-]+\.gguf)[[:space:]]*$' "$preset" | ${pkgs.gnugrep}/bin/grep -q .; then
      echo "llama preset may contain only version, one local model section, and one /srv/models GGUF" >&2
      exit 1
    fi

    model_lines="$(${pkgs.gnugrep}/bin/grep -Ec '^[[:space:]]*model[[:space:]]*=[[:space:]]*/srv/models/[A-Za-z0-9._/-]+\.gguf[[:space:]]*$' "$preset" || true)"
    all_model_lines="$(${pkgs.gnugrep}/bin/grep -Ec '^[[:space:]]*model[[:space:]]*=' "$preset" || true)"
    sections="$(${pkgs.gnugrep}/bin/grep -Ec '^[[:space:]]*\[[^*][^]]*\][[:space:]]*$' "$preset" || true)"
    test "$model_lines" -eq 1
    test "$all_model_lines" -eq 1
    test "$sections" -eq 1

    model="$(${pkgs.gnused}/bin/sed -nE 's|^[[:space:]]*model[[:space:]]*=[[:space:]]*(/srv/models/[A-Za-z0-9._/-]+\.gguf)[[:space:]]*$|\1|p' "$preset")"
    canonical="$(${pkgs.coreutils}/bin/realpath -e "$model")"
    case "$canonical" in
      /srv/models/*) ;;
      *) echo "llama model escapes /srv/models" >&2; exit 1 ;;
    esac
    test -f "$canonical"
  '';
in
{
  options.balaur.sharedServices.llama = {
    package = lib.mkOption {
      type = lib.types.package;
      default = llamaPackage;
      description = "Pinned llama.cpp b9190 ROCm package; replace only in disposable tests.";
    };

    readiness = {
      ready = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Human-controlled production gate. It may become true only after a
          physical benchmark approves one preset and both owner API keys exist
          as encrypted owner-policy runtime files.
        '';
      };

      modelPresetFile = lib.mkOption {
        type = lib.types.nullOr (lib.types.strMatching "^/srv/models/[a-zA-Z0-9._/-]+\\.ini$");
        default = null;
        description = "Runtime path to the benchmark-approved, single-model router preset.";
      };

      ownerApiKeyFiles = {
        alex = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.strMatching "^/run/balaur-secrets/owners/alex/llama/[a-zA-Z0-9._-]+$"
          );
          default = null;
          description = "Alex's runtime-only llama API key file.";
        };
        andreea = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.strMatching "^/run/balaur-secrets/owners/andreea/llama/[a-zA-Z0-9._-]+$"
          );
          default = null;
          description = "Andreea's runtime-only llama API key file.";
        };
      };

      memoryHighBytes = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = ''
          Soft cgroup ceiling derived from the approved benchmark's peak
          inference memory plus reviewed margin. MemoryHigh throttles optional
          inference under pressure; there is intentionally no guessed hard
          MemoryMax and no MemoryLow protection competing with Jellyfin.
        '';
      };
    };

    backend = {
      host = lib.mkOption {
        type = lib.types.enum [ "127.0.0.1" ];
        readOnly = true;
        default = "127.0.0.1";
        description = "Loopback-only raw router address.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        readOnly = true;
        default = 8081;
        description = "Private raw router port; never opened by the firewall or Caddy.";
      };
    };

  };

  config = lib.mkMerge [
    {
      assertions = [
        {
          assertion =
            !cfg.readiness.ready
            || (
              cfg.readiness.modelPresetFile != null
              && cfg.readiness.ownerApiKeyFiles.alex != null
              && cfg.readiness.ownerApiKeyFiles.andreea != null
              && cfg.readiness.memoryHighBytes != null
              && lib.hasPrefix "${ownerSecretRoot "alex"}/llama/" cfg.readiness.ownerApiKeyFiles.alex
              && lib.hasPrefix "${ownerSecretRoot "andreea"}/llama/" cfg.readiness.ownerApiKeyFiles.andreea
              && cfg.readiness.ownerApiKeyFiles.alex != cfg.readiness.ownerApiKeyFiles.andreea
            );
          message = "Enabling llama requires one /srv/models preset, distinct owner-policy API key files, and a benchmark-derived MemoryHigh value";
        }
      ];

      warnings = lib.optional (!cfg.readiness.ready) ''
        DEPLOYMENT BLOCKER: llama.cpp is disabled pending the four-candidate physical benchmark, a benchmark-approved single-model preset under /srv/models, separate sops-backed owner API keys, and issue 12 private owner-container forwarding.
      '';
    }

    (lib.mkIf cfg.readiness.ready {
      users.groups.llama = { };
      users.users.llama = {
        isSystemUser = true;
        group = "llama";
        extraGroups = [
          "render"
          "video"
        ];
      };

      # b9190 source evidence:
      # - tools/server/server-context.cpp handle_sleeping_state() calls destroy(),
      #   which resets llama_init and frees model/context/batch resources;
      # - tools/server/README.md "Sleeping on Idle" says model and KV memory are
      #   unloaded and lazily reloaded;
      # - docs/build.md HIP/Unified Memory prescribes this runtime variable.
      # It is not an HSA_XNACK setting and no HSA override is guessed here.
      systemd.services.llama-router = {
        description = "Private lazy llama.cpp ROCm router";
        wantedBy = [ "multi-user.target" ];
        requires = [ "local-fs.target" ];
        after = [ "local-fs.target" ];
        unitConfig = {
          RequiresMountsFor = [ "/srv/models" ];
          ConditionPathIsMountPoint = [ "/srv/models" ];
        };
        environment = {
          GGML_CUDA_ENABLE_UNIFIED_MEMORY = "1";
          LLAMA_CACHE = "/srv/models/.llama-router-disabled-cache";
          LLAMA_OFFLINE = "1";
          HOME = runtimeDirectory;
        };
        preStart = ''
          set -eu
          ${validatePreset} ${lib.escapeShellArg cfg.readiness.modelPresetFile}
          umask 077
          : > ${apiKeyFile}
          for credential in alex-api-key andreea-api-key; do
            key="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/$credential")"
            test "$(${pkgs.coreutils}/bin/printf '%s' "$key" | ${pkgs.coreutils}/bin/wc -l)" -eq 0
            ${pkgs.coreutils}/bin/printf '%s\n' "$key" | ${pkgs.gnugrep}/bin/grep -Eq '^[A-Za-z0-9_-]{32,}$'
            ${pkgs.coreutils}/bin/printf '%s\n' "$key" >> ${apiKeyFile}
          done
          test "$(${pkgs.coreutils}/bin/sort -u ${apiKeyFile} | ${pkgs.coreutils}/bin/wc -l)" -eq 2
        '';
        serviceConfig = {
          ExecStart = lib.escapeShellArgs serverArgs;
          User = "llama";
          Group = "llama";
          RuntimeDirectory = "llama-router";
          RuntimeDirectoryMode = "0700";
          LoadCredential = [
            "alex-api-key:${cfg.readiness.ownerApiKeyFiles.alex}"
            "andreea-api-key:${cfg.readiness.ownerApiKeyFiles.andreea}"
          ];
          Restart = "on-failure";
          RestartSec = 10;

          CPUWeight = 100;
          IOWeight = 100;
          IOSchedulingPriority = 4;
          MemoryAccounting = true;
          MemoryHigh = toString cfg.readiness.memoryHighBytes;
          ManagedOOMMemoryPressure = "kill";
          OOMScoreAdjust = 500;
          OOMPolicy = "stop";
          LimitMEMLOCK = "infinity";

          PrivateDevices = true;
          DeviceAllow = [
            "/dev/kfd rw"
            "/dev/dri/renderD128 rw"
            "char-drm rw"
          ];
          IPAddressDeny = "any";
          IPAddressAllow = [
            "127.0.0.0/8"
            "::1/128"
          ];
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          ReadOnlyPaths = [ "/srv/models" ];
        };
      };
    })
  ];
}
