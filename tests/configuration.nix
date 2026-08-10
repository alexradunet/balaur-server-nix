{ config, pkgs }:

let
  inherit (pkgs) lib;

  hardened =
    service:
    let
      serviceConfig = config.systemd.services.${service}.serviceConfig;
    in
    serviceConfig.CapabilityBoundingSet == ""
    && serviceConfig.NoNewPrivileges
    && serviceConfig.PrivateDevices
    && serviceConfig.PrivateTmp
    && serviceConfig.ProtectSystem == "strict"
    && serviceConfig.RestrictNamespaces;

  assertions = [
    {
      assertion = config.networking.hostName == "balaur" && config.system.stateVersion == "26.05";
      message = "host identity and state version must remain stable";
    }
    {
      assertion = config.nixpkgs.hostPlatform.system == "x86_64-linux";
      message = "the host must target x86_64-linux";
    }
    {
      assertion =
        map (boot: boot.path) config.boot.loader.grub.mirroredBoots == [
          "/boot"
          "/boot-fallback"
        ];
      message = "GRUB must be mirrored to both EFI partitions";
    }
    {
      assertion =
        config.fileSystems."/".device == "/dev/disk/by-uuid/3833ed98-7e78-4c5c-afa2-326cb47c0fd6"
        && config.fileSystems."/boot".device == "/dev/disk/by-uuid/9A81-7B8A"
        && config.fileSystems."/boot-fallback".device == "/dev/disk/by-uuid/9A81-CE59";
      message = "the root and redundant EFI filesystems must use the installed disk UUIDs";
    }
    {
      assertion = config.boot.swraid.enable && config.hardware.cpu.amd.updateMicrocode;
      message = "RAID and AMD microcode support must stay enabled";
    }
    {
      assertion =
        config.fileSystems."/mnt/balaur-backup".device == "/dev/disk/by-label/BALAUR_BACKUP"
        && builtins.elem "noauto" config.fileSystems."/mnt/balaur-backup".options
        && builtins.elem "d /mnt/balaur-backup 0700 root root -" config.systemd.tmpfiles.rules
        && config.systemd.timers.balaur-backup.timerConfig.OnCalendar == "daily"
        && config.systemd.timers.balaur-backup.timerConfig.Persistent
        &&
          config.systemd.services.balaur-backup.serviceConfig.LoadCredential
          == "passphrase:/var/lib/balaur-backup/passphrase"
        && config.systemd.services.balaur-backup.serviceConfig.Type == "oneshot"
        &&
          config.systemd.services.balaur-backup.unitConfig.ConditionPathExists
          == "/dev/disk/by-label/BALAUR_BACKUP";
      message = "the daily encrypted USB backup must mount on demand and always unmount afterward";
    }
    {
      assertion =
        config.services.openssh.enable
        && config.services.openssh.settings.AllowUsers == [ "alex" ]
        && !config.services.openssh.settings.KbdInteractiveAuthentication
        && config.services.openssh.settings.PermitRootLogin == "no"
        && config.services.openssh.settings.PasswordAuthentication
        && !config.services.openssh.settings.X11Forwarding;
      message = "SSH must only permit alex, reject root, and disable unused authentication and forwarding features";
    }
    {
      assertion =
        config.networking.firewall.allowedTCPPorts == [ 22 ]
        && config.networking.firewall.allowedUDPPorts == [ ]
        && lib.all (port: !builtins.elem port config.networking.firewall.allowedTCPPorts) [
          80
          443
          3000
          4000
          6080
          6768
          7681
          8080
          8081
          8082
          8383
          22000
        ];
      message = "SSH must be the only TCP service exposed through the firewall";
    }
    {
      assertion =
        config.services.llama-cpp.host == "127.0.0.1"
        && config.services.llama-cpp.port == 8081
        && config.services.syncthing.guiAddress == "127.0.0.1:8383"
        && !config.services.syncthing.openDefaultPorts
        && config.systemd.services.balaur-dashboard.environment.DASHBOARD_HOST == "127.0.0.1"
        && config.systemd.services.herdr-web.environment.HERDR_WEB_LISTEN == "127.0.0.1";
      message = "application services must bind to loopback for SSH forwarding";
    }
    {
      assertion =
        !config.services.headscale.enable
        && !config.services.headplane.enable
        && !config.services.nginx.enable
        && !config.services.tailscale.enable
        && config.services.llama-cpp.enable
        && config.services.syncthing.enable
        &&
          lib.all (service: builtins.elem "multi-user.target" config.systemd.services.${service}.wantedBy)
            [
              "balaur-dashboard"
              "herdr-web"
              "web-desktop-novnc"
              "web-desktop-session"
              "web-desktop-vnc"
            ];
      message = "VPN and public web ingress must remain disabled while local services start at boot";
    }
    {
      assertion = lib.all hardened [
        "balaur-dashboard"
        "web-desktop-novnc"
      ];
      message = "network-facing custom services must retain their systemd sandboxing";
    }
    {
      assertion = lib.hasInfix "--listen 127.0.0.1:6080" config.systemd.services.web-desktop-novnc.serviceConfig.ExecStart;
      message = "noVNC must only listen on loopback";
    }
    {
      assertion =
        config.services.llama-cpp.package.version == "10336"
        &&
          config.services.llama-cpp.extraFlags == [
            "--hf-repo"
            "unsloth/gemma-4-26B-A4B-it-GGUF:UD-Q4_K_M"
            "--ctx-size"
            "65536"
            "--parallel"
            "2"
            "--n-gpu-layers"
            "999"
            "--flash-attn"
            "on"
            "--spec-type"
            "draft-mtp"
            "--spec-draft-n-max"
            "4"
          ]
        && config.hardware.graphics.enable
        && config.systemd.services.llama-cpp.environment.XDG_CACHE_HOME == "/var/cache/llama-cpp"
        && config.systemd.services.llama-cpp.serviceConfig.ProcSubset == "all"
        && builtins.elem "-DGGML_HIP:BOOL=TRUE" config.services.llama-cpp.package.cmakeFlags
        && builtins.elem "-DGGML_VULKAN:BOOL=FALSE" config.services.llama-cpp.package.cmakeFlags;
      message = "llama.cpp must load Gemma 4 with GPU offload and MTP speculative decoding";
    }
  ];

  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur configuration invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-configuration-tests" { } ''
    grep --fixed-strings -- '-interface 127.0.0.1' ${config.systemd.services.web-desktop-vnc.serviceConfig.ExecStart}
    grep --fixed-strings -- '-rfbport 5910' ${config.systemd.services.web-desktop-vnc.serviceConfig.ExecStart}
    grep --fixed-strings -- '--writable' ${config.systemd.services.herdr-web.serviceConfig.ExecStart}
    grep --fixed-strings -- '--check-origin' ${config.systemd.services.herdr-web.serviceConfig.ExecStart}
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} configuration invariants passed.' > "$out/result"
  ''
