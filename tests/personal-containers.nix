{
  defaultConfig,
  readyConfig,
  pkgs,
}:

let
  inherit (pkgs) lib;
  owners = [
    "alex"
    "andreea"
  ];
  expected = {
    alex = {
      hostAddress = "10.231.12.1";
      localAddress = "10.231.12.2";
      gid = 991;
    };
    andreea = {
      hostAddress = "10.231.13.1";
      localAddress = "10.231.13.2";
      gid = 992;
    };
  };
  expectedVersions = {
    trilium = "0.102.2";
    paperless = "2.20.15";
    firefly = "6.6.3";
    importer = "2.3.4";
    openWebui = "0.11.0";
  };
  appFragments = [
    "firefly"
    "open-webui"
    "paperless"
    "trilium"
  ];
  hostPersonalServices =
    config:
    builtins.filter (service: lib.any (fragment: lib.hasInfix fragment service) appFragments) (
      builtins.attrNames config.systemd.services
    );
  expectedBinds = owner: {
    "/run/owner-secrets" = {
      hostPath = "/run/balaur-secrets/owners/${owner}";
      isReadOnly = true;
      mountPoint = "/run/owner-secrets";
    };
    "/srv/paperless/consume" = {
      hostPath = "/home/${owner}/files/paperless-consume";
      isReadOnly = false;
      mountPoint = "/srv/paperless/consume";
    };
    "/srv/personal" = {
      hostPath = "/srv/people/${owner}/apps";
      isReadOnly = false;
      mountPoint = "/srv/personal";
    };
  };
  appUnits = [
    "firefly-iii-setup"
    "firefly-iii-data-importer-setup"
    "nginx"
    "open-webui"
    "paperless-scheduler"
    "paperless-web"
    "postgresql"
    "redis-paperless"
    "trilium-server"
  ];
  missingUnitGates = lib.concatMap (
    owner:
    let
      inner = readyConfig.containers."${owner}-personal".config;
    in
    map (unit: "${owner}:${unit}") (
      builtins.filter (
        unit:
        !(builtins.elem "personal-stack-secrets.service" inner.systemd.services.${unit}.requires)
        || !(builtins.elem "personal-stack-version-gate.service" inner.systemd.services.${unit}.requires)
      ) appUnits
    )
  ) owners;
  assertions = [
    {
      assertion =
        builtins.attrNames defaultConfig.containers == [
          "alex-personal"
          "andreea-personal"
        ]
        && hostPersonalServices defaultConfig == [ ]
        && lib.all (
          owner:
          let
            container = defaultConfig.containers."${owner}-personal";
          in
          !container.autoStart
          && container.ephemeral
          && container.privateNetwork
          && container.privateUsers == "identity"
          && !container.restartIfChanged
          && container.bindMounts == expectedBinds owner
          &&
            container.tmpfs == [
              "/srv/personal/open-webui/cache"
              "/tmp"
              "/var/tmp"
            ]
        ) owners;
      message = "the default host must declare exact owner containers while keeping every personal app and missing runtime file disabled";
    }
    {
      assertion =
        defaultConfig.balaur.personalContainers.approvedVersions == expectedVersions
        && !defaultConfig.balaur.personalContainers.owners.alex.readiness.ready
        && !defaultConfig.balaur.personalContainers.owners.andreea.readiness.ready
        && lib.all (
          owner:
          lib.any (warning: lib.hasInfix "${owner}-personal is disabled" warning) defaultConfig.warnings
        ) owners;
      message = "production readiness and approved migration versions must remain explicit and fail closed";
    }
    {
      assertion =
        hostPersonalServices readyConfig == [ ]
        && lib.all (
          owner:
          let
            policy = readyConfig.balaur.personalContainers.owners.${owner};
            container = readyConfig.containers."${owner}-personal";
            inner = container.config;
          in
          policy.readiness.ready
          && policy.readiness.importerReady
          && container.autoStart
          && container.hostAddress == expected.${owner}.hostAddress
          && container.localAddress == expected.${owner}.localAddress
          && container.bindMounts == expectedBinds owner
          && readyConfig.users.groups."paperless-consume-${owner}".gid == expected.${owner}.gid
          && inner.users.groups."paperless-consume-${owner}".gid == expected.${owner}.gid
          && inner.services.trilium-server.enable
          && inner.services.trilium-server.package.version == expectedVersions.trilium
          && inner.services.paperless.enable
          && inner.services.paperless.package.version == expectedVersions.paperless
          && inner.services.firefly-iii.enable
          && inner.services.firefly-iii.package.version == expectedVersions.firefly
          && inner.services.firefly-iii-data-importer.enable
          && inner.services.firefly-iii-data-importer.package.version == expectedVersions.importer
          && inner.services.open-webui.enable
          && inner.services.open-webui.package.version == expectedVersions.openWebui
          && inner.services.open-webui.environment.ENABLE_SIGNUP == "False"
          && inner.services.open-webui.environment.WEBUI_ADMIN_EMAIL == "${owner}@home.arpa"
        ) owners;
      message = "the ready fixture must evaluate all five pinned native modules independently in both containers and never on the host";
    }
    {
      assertion = lib.all (
        owner:
        let
          inner = readyConfig.containers."${owner}-personal".config;
        in
        inner.services.postgresql.package.version == "17.10"
        && inner.services.postgresql.dataDir == "/srv/personal/postgresql/17"
        && !inner.services.postgresql.enableTCPIP
        && builtins.elem "paperless" inner.services.postgresql.ensureDatabases
        && builtins.elem "firefly-iii" inner.services.postgresql.ensureDatabases
        && inner.services.redis.package.version == "8.8.1"
        && inner.services.redis.servers.paperless.port == 0
        && inner.services.redis.servers.paperless.save == [ ]
        && inner.services.paperless.settings.PAPERLESS_TASK_WORKERS == 1
        && inner.services.paperless.consumptionDir == "/srv/paperless/consume"
        && inner.services.open-webui.stateDir == "/srv/personal/open-webui"
        && inner.services.open-webui.environment.HF_HOME == "/srv/personal/open-webui/cache/huggingface"
        &&
          inner.services.open-webui.environment.WHISPER_MODEL_DIR == "/srv/personal/open-webui/cache/whisper"
      ) owners;
      message = "each owner must have only its own Unix-socket PostgreSQL/Redis and exact fresh state/consume paths";
    }
    {
      assertion = lib.all (
        owner:
        let
          inner = readyConfig.containers."${owner}-personal".config;
        in
        lib.all (
          unit:
          builtins.elem "personal-stack-secrets.service" inner.systemd.services.${unit}.requires
          && builtins.elem "personal-stack-version-gate.service" inner.systemd.services.${unit}.requires
        ) appUnits
        && inner.systemd.services.personal-stack-secrets.serviceConfig.RuntimeDirectoryMode == "0711"
        && inner.systemd.services.open-webui.serviceConfig.DynamicUser == false
        && inner.systemd.services.open-webui.serviceConfig.CPUWeight == 50
        && inner.systemd.slices.system-paperless.sliceConfig.CPUWeight == 200
      ) owners;
      message = "every app/setup unit must require runtime secret and migration gates, with optional chat below Paperless under pressure; missing: ${lib.concatStringsSep "," missingUnitGates}";
    }
    {
      assertion = lib.all (
        owner:
        let
          unit = readyConfig.systemd.services."container@${owner}-personal";
        in
        unit.serviceConfig.CPUWeight == 100
        && unit.serviceConfig.IOWeight == 100
        && unit.serviceConfig.MemoryAccounting
        && unit.serviceConfig.ManagedOOMMemoryPressure == "kill"
        && unit.serviceConfig.ManagedOOMMemoryPressureLimit == "80%"
        && !(unit.serviceConfig ? MemoryMax)
        &&
          unit.unitConfig.ConditionPathIsMountPoint == [
            "/srv/people/${owner}/apps"
            "/home/${owner}"
          ]
      ) owners;
      message = "both containers must have equal soft resource policy and fail closed when either owner ZFS mount is absent";
    }
    {
      assertion =
        readyConfig.balaur.ingress.reverseProxies."notes.alex.home.arpa".backend == {
          host = "10.231.12.2";
          port = 8080;
        }
        &&
          readyConfig.balaur.ingress.reverseProxies."paperless.andreea.home.arpa".backend == {
            host = "10.231.13.2";
            port = 28981;
          }
        && readyConfig.balaur.ingress.reverseProxies."budget.alex.home.arpa".backend.port == 80
        && readyConfig.balaur.ingress.reverseProxies."chat.andreea.home.arpa".backend.port == 3000
        &&
          readyConfig.balaur.ingress.reverseProxies."importer.alex.home.arpa".backend == {
            host = "10.231.12.2";
            port = 80;
          };
      message = "Caddy must register the approved owner app names against private container addresses, with Importer gated separately";
    }
    {
      assertion =
        readyConfig.systemd.services.caddy.serviceConfig.LoadCredential == [
          "importer-alex-password:/run/balaur-secrets/owners/alex/personal/importer-proxy-password"
          "importer-andreea-password:/run/balaur-secrets/owners/andreea/personal/importer-proxy-password"
        ]
        && lib.hasInfix "caddy hash-password --algorithm bcrypt" readyConfig.systemd.services.caddy.preStart
        &&
          lib.hasInfix "import /run/caddy-importer-auth/alex.caddy"
            readyConfig.services.caddy.virtualHosts."importer.alex.home.arpa".extraConfig
        && lib.hasInfix "-d 10.0.0.0/8 -j REJECT" readyConfig.networking.firewall.extraCommands
        && lib.hasInfix "-d 192.168.0.0/16 -j REJECT" readyConfig.networking.firewall.extraCommands
        && lib.all (
          owner:
          !readyConfig.containers."${owner}-personal".config.networking.enableIPv6
          &&
            lib.hasInfix "readlink -e /home/${owner}/files"
              readyConfig.systemd.services."personal-storage-${owner}".script
          &&
            lib.hasInfix "findmnt -rn -T /home/${owner}/files"
              readyConfig.systemd.services."personal-storage-${owner}".script
          && lib.hasInfix "setfacl -m u:0:rwx" readyConfig.systemd.services."personal-storage-${owner}".script
        ) owners;
      message = "Importer must have runtime Caddy authentication while private-range egress, IPv6 bypass, and identity-map mount access stay closed";
    }
    {
      assertion = lib.all (
        owner:
        let
          root = "/run/balaur-secrets/owners/${owner}";
          binds = readyConfig.containers."${owner}-personal".bindMounts;
        in
        binds."/run/owner-secrets".hostPath == root
        && binds."/run/owner-secrets".isReadOnly
        && !lib.any (
          mount:
          mount.hostPath == "/run"
          || mount.hostPath == "/run/balaur-secrets"
          || lib.hasInfix (if owner == "alex" then "andreea" else "alex") mount.hostPath
        ) (builtins.attrValues binds)
      ) owners;
      message = "each container must receive only its exact owner secret root and never full /run, a global root, or the other owner";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur personal-container invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-personal-containers-tests" { } ''
    mkdir -p "$out"
    printf '%s\n' 'All ${toString (builtins.length assertions)} personal-container invariants passed.' > "$out/result"
  ''
