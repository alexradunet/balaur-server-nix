{ config, pkgs }:

let
  inherit (pkgs) lib;

  tailnetOnly =
    location:
    lib.all (directive: lib.hasInfix directive location.extraConfig) [
      "allow 100.64.0.0/10;"
      "allow fd7a:115c:a1e0::/48;"
      "deny all;"
    ];

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
        config.services.openssh.enable
        && config.services.openssh.settings.AllowUsers == [ "alex" ]
        && config.services.openssh.settings.PermitRootLogin == "no"
        && config.services.openssh.settings.PasswordAuthentication;
      message = "SSH must only permit the alex account and must reject root";
    }
    {
      assertion =
        lib.all (port: builtins.elem port config.networking.firewall.allowedTCPPorts) [
          22
          80
          443
        ]
        && lib.all (port: !builtins.elem port config.networking.firewall.allowedTCPPorts) [
          3000
          4000
          6080
          6768
          8080
          8082
          8383
        ];
      message = "web application ports must not be directly exposed through the firewall";
    }
    {
      assertion =
        config.services.headscale.address == "127.0.0.1"
        && config.services.headscale.port == 8082
        && config.services.syncthing.guiAddress == "127.0.0.1:8383"
        && config.services.paseo.listenAddress == "127.0.0.1"
        && config.services.paseo.port == 6768
        && config.systemd.services.balaur-dashboard.environment.DASHBOARD_HOST == "127.0.0.1"
        && config.systemd.services.paseo-relay.environment.PASEO_RELAY_HOST == "127.0.0.1";
      message = "proxied application services must bind to loopback";
    }
    {
      assertion =
        map (record: record.name) config.services.headscale.settings.dns.extra_records == [
          "dashboard.balaur.space"
          "desktop.balaur.space"
          "paseo.balaur.space"
          "syncthing.balaur.space"
        ]
        && lib.all (
          record: record.value == "100.64.0.1"
        ) config.services.headscale.settings.dns.extra_records;
      message = "MagicDNS must direct private services to the tailnet address";
    }
    {
      assertion =
        config.services.nginx.virtualHosts."balaur".locations."/".return
        == "302 https://dashboard.balaur.space$request_uri"
        &&
          config.services.nginx.virtualHosts."dashboard.balaur.space".locations."/".proxyPass
          == "http://127.0.0.1:8080"
        &&
          config.services.nginx.virtualHosts."headscale.balaur.space".locations."/".proxyPass
          == "http://127.0.0.1:8082"
        &&
          config.services.nginx.virtualHosts."relay.balaur.space".locations."/".proxyPass
          == "http://127.0.0.1:4000"
        &&
          config.services.nginx.virtualHosts."syncthing.balaur.space".locations."/".proxyPass
          == "http://127.0.0.1:8383"
        &&
          config.services.nginx.virtualHosts."paseo.balaur.space".locations."/".proxyPass
          == "http://127.0.0.1:6768"
        &&
          config.services.nginx.virtualHosts."desktop.balaur.space".locations."/".proxyPass
          == "http://127.0.0.1:6080";
      message = "nginx must route every endpoint to its intended loopback service";
    }
    {
      assertion = lib.all tailnetOnly [
        config.services.nginx.virtualHosts."dashboard.balaur.space".locations."/"
        config.services.nginx.virtualHosts."balaur.tailnet.balaur.space".locations."/"
        config.services.nginx.virtualHosts."syncthing.balaur.space".locations."/"
        config.services.nginx.virtualHosts."paseo.balaur.space".locations."/"
        config.services.nginx.virtualHosts."desktop.balaur.space".locations."/"
      ];
      message = "private nginx endpoints must enforce both tailnet ranges and deny all other clients";
    }
    {
      assertion =
        config.services.headscale.enable
        && config.services.headplane.enable
        && config.services.nginx.enable
        && config.services.tailscale.enable
        && config.services.syncthing.enable
        && config.services.paseo.enable
        &&
          lib.all (service: builtins.elem "multi-user.target" config.systemd.services.${service}.wantedBy)
            [
              "balaur-dashboard"
              "paseo-relay"
              "web-desktop-novnc"
              "web-desktop-session"
              "web-desktop-vnc"
            ];
      message = "all declared server services must remain enabled at boot";
    }
    {
      assertion =
        config.services.paseo.relay.mode == "remote"
        && config.services.paseo.relay.host == "relay.balaur.space"
        && config.services.paseo.relay.port == 443
        && config.services.paseo.relay.useTls;
      message = "Paseo must use the public TLS relay endpoint";
    }
    {
      assertion =
        lib.hasInfix "umask 077" config.systemd.services.headplane.preStart
        && lib.hasInfix "/var/lib/headplane/cookie-secret" config.systemd.services.headplane.preStart;
      message = "Headplane must generate its cookie secret at runtime with restrictive permissions";
    }
    {
      assertion = lib.all hardened [
        "balaur-dashboard"
        "paseo-relay"
        "web-desktop-novnc"
      ];
      message = "network-facing custom services must retain their systemd sandboxing";
    }
    {
      assertion = lib.hasInfix "--listen 127.0.0.1:6080" config.systemd.services.web-desktop-novnc.serviceConfig.ExecStart;
      message = "noVNC must only listen on loopback";
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
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} configuration invariants passed.' > "$out/result"
  ''
