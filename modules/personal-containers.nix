{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.balaur.personalContainers;
  owners = [
    "alex"
    "andreea"
  ];
  llamaReadyFor =
    owner: config.balaur.sharedServices.llama.readiness.ready && cfg.owners.${owner}.readiness.ready;

  approvedVersions = {
    trilium = "0.102.2";
    paperless = "2.20.15";
    firefly = "6.6.3";
    importer = "2.3.4";
    openWebui = "0.11.0";
  };
  approvedVersionsText = ''
    trilium-server=${approvedVersions.trilium}
    paperless-ngx=${approvedVersions.paperless}
    firefly-iii=${approvedVersions.firefly}
    firefly-iii-data-importer=${approvedVersions.importer}
    open-webui=${approvedVersions.openWebui}
  '';
  approvedVersionsFile = pkgs.writeText "personal-stack-approved-versions" approvedVersionsText;
  preparedOwnerAppsAcl = pkgs.writeText "personal-stack-prepared-apps.acl" ''
    user::rwx
    user:0:rwx
    user:71:--x
    user:315:--x
    user:900:--x
    user:901:--x
    user:902:--x
    user:903:--x
    user:904:--x
    group::---
    mask::rwx
    other::---

  '';
  preparedConsumeAcl = pkgs.writeText "personal-stack-prepared-consume.acl" ''
    user::rwx
    user:0:rwx
    group::rwx
    mask::rwx
    other::---

  '';

  ownerDefaults = {
    alex = {
      hostAddress = "10.231.12.1";
      localAddress = "10.231.12.2";
      consumeGroupId = 991;
    };
    andreea = {
      hostAddress = "10.231.13.1";
      localAddress = "10.231.13.2";
      consumeGroupId = 992;
    };
  };

  secretFileType = lib.types.nullOr (
    lib.types.strMatching "^/run/balaur-secrets/owners/(alex|andreea)/personal/[a-zA-Z0-9._-]+$"
  );
  ownerType = lib.types.submodule (
    { name, ... }:
    {
      options = {
        hostAddress = lib.mkOption {
          type = lib.types.strMatching "^10\\.231\\.[0-9]{1,3}\\.[0-9]{1,3}$";
          default = ownerDefaults.${name}.hostAddress;
          readOnly = true;
          description = "Stable host side of this owner's point-to-point container link.";
        };
        localAddress = lib.mkOption {
          type = lib.types.strMatching "^10\\.231\\.[0-9]{1,3}\\.[0-9]{1,3}$";
          default = ownerDefaults.${name}.localAddress;
          readOnly = true;
          description = "Stable private address of this owner's container.";
        };
        consumeGroupId = lib.mkOption {
          type = lib.types.ints.between 900 999;
          default = ownerDefaults.${name}.consumeGroupId;
          readOnly = true;
          description = "Explicit host/container group ID for the narrow Paperless inbox.";
        };
        readiness = {
          ready = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable this fresh personal stack only after its real owner payload and version marker exist.";
          };
          importerReady = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Enable the Data Importer after Firefly onboarding has produced this owner's access token.";
          };
          openWebuiAdminEmail = lib.mkOption {
            type = lib.types.nullOr (lib.types.strMatching "^[^@[:space:]]+@[^@[:space:]]+$");
            default = null;
            description = "Owner-chosen Open WebUI login email; non-secret but required for closed bootstrap.";
          };
          files = {
            paperlessAdminPassword = lib.mkOption {
              type = secretFileType;
              default = null;
              description = "Human-chosen initial Paperless admin password runtime file.";
            };
            fireflyAppKey = lib.mkOption {
              type = secretFileType;
              default = null;
              description = "Persistent Firefly APP_KEY runtime file.";
            };
            fireflyCronToken = lib.mkOption {
              type = secretFileType;
              default = null;
              description = "Exactly 32-character Firefly static cron token runtime file.";
            };
            openWebuiSecretKey = lib.mkOption {
              type = secretFileType;
              default = null;
              description = "Persistent Open WebUI encryption/JWT key runtime file.";
            };
            openWebuiAdminPassword = lib.mkOption {
              type = secretFileType;
              default = null;
              description = "Human-chosen initial Open WebUI owner-admin password runtime file.";
            };
            importerAccessToken = lib.mkOption {
              type = secretFileType;
              default = null;
              description = "Owner-local Firefly personal access token for the Data Importer.";
            };
            importerProxyPassword = lib.mkOption {
              type = secretFileType;
              default = null;
              description = "Owner-only password for Caddy authentication in front of the otherwise unauthenticated Data Importer UI.";
            };
          };
        };
      };
    }
  );

  ownerSecretRoot = owner: config.balaur.secrets.policies.${owner}.runtimeDirectory;
  ownerApps = owner: "/srv/people/${owner}/apps";
  ownerHome = owner: "/home/${owner}";
  ownerConsume = owner: "/home/${owner}/files/paperless-consume";
  versionMarker = owner: "${ownerApps owner}/approved-versions";
  consumeGroup = owner: "paperless-consume-${owner}";
  containerName = owner: "${owner}-personal";
  hostInterfacePattern = owner: "ve-${owner}+";

  requiredBaseFiles =
    readiness: with readiness.files; [
      paperlessAdminPassword
      fireflyAppKey
      fireflyCronToken
      openWebuiSecretKey
      openWebuiAdminPassword
    ];
  filesAreOwnerScoped =
    owner: files:
    lib.all (path: path == null || lib.hasPrefix "${ownerSecretRoot owner}/personal/" path) files;

  mkCredential = name: path: "${name}:${path}";
  credentialBaseName = path: builtins.baseNameOf path;
  triliumConfigFile =
    owner: address:
    pkgs.writeText "trilium-config-${owner}.ini" ''
      [General]
      instanceName=Trilium
      noDesktopIcon=true
      noBackup=false
      noAuthentication=false

      [Network]
      host=${address}
      port=8080
      https=false
    '';

  mkContainerConfig =
    owner: ownerCfg:
    let
      readiness = ownerCfg.readiness;
      secretFiles = readiness.files;
      hostAddress = ownerCfg.hostAddress;
      localAddress = ownerCfg.localAddress;
      notesName = "notes.${owner}.home.arpa";
      paperlessName = "paperless.${owner}.home.arpa";
      budgetName = "budget.${owner}.home.arpa";
      chatName = "chat.${owner}.home.arpa";
      importerName = "importer.${owner}.home.arpa";
      llamaReady = llamaReadyFor owner;
      llamaHostFile = config.balaur.sharedServices.llama.readiness.ownerApiKeyFiles.${owner};
      llamaContainerFile =
        if llamaHostFile == null then
          null
        else
          "/run/owner-secrets/llama/${credentialBaseName llamaHostFile}";
      gateUnits = [
        "personal-stack-secrets.service"
        "personal-stack-version-gate.service"
      ];
      guardedServices = [
        "postgresql"
        "postgresql-setup"
        "redis-paperless"
        "trilium-server"
        "paperless-scheduler"
        "paperless-task-queue"
        "paperless-consumer"
        "paperless-web"
        "firefly-iii-setup"
        "firefly-iii-cron"
        "phpfpm-firefly-iii"
        "nginx"
        "open-webui"
      ]
      ++ lib.optionals readiness.importerReady [
        "firefly-iii-data-importer-setup"
        "phpfpm-firefly-iii-data-importer"
      ];
    in
    {
      config =
        {
          lib,
          pkgs,
          ...
        }:
        {
          nixpkgs.config.allowUnfreePredicate = package: lib.getName package == "open-webui";
          system.stateVersion = "26.05";
          time.timeZone = "Europe/Bucharest";

          assertions = [
            {
              assertion =
                pkgs.trilium-server.version == approvedVersions.trilium
                && pkgs.paperless-ngx.version == approvedVersions.paperless
                && pkgs.firefly-iii.version == approvedVersions.firefly
                && pkgs.firefly-iii-data-importer.version == approvedVersions.importer
                && pkgs.open-webui.version == approvedVersions.openWebui;
              message = "${owner}'s personal stack packages changed; update the reviewed versions and runtime marker before migration";
            }
          ];

          networking = {
            enableIPv6 = false;
            nameservers = [ cfg.egressResolver ];
            useHostResolvConf = false;
            firewall = {
              enable = true;
              allowPing = false;
              # The container has only loopback plus its dedicated point-to-point
              # veth; host forwarding rules prevent LAN or peer-container routes.
              allowedTCPPorts = [
                80
                8080
                3000
                28981
              ];
              allowedUDPPorts = [ ];
            };
            extraHosts = ''
              127.0.0.1 ${budgetName} ${importerName}
            '';
          };

          users = {
            mutableUsers = false;
            # Containers have no SSH/admin account by design; host Alex enters
            # them with machinectl when recovery is required.
            allowNoPasswordLogin = true;
            groups = lib.mkIf readiness.ready {
              trilium.gid = 900;
              open-webui.gid = 903;
              redis-paperless.gid = 904;
              ${consumeGroup owner}.gid = ownerCfg.consumeGroupId;
            };
            users = lib.mkIf readiness.ready {
              trilium.uid = 900;
              firefly-iii.uid = 901;
              firefly-iii-data-importer.uid = 902;
              open-webui = {
                uid = 903;
                isSystemUser = true;
                group = "open-webui";
                home = "/srv/personal/open-webui";
              };
              redis-paperless.uid = 904;
              paperless.extraGroups = [ (consumeGroup owner) ];
            };
          };

          services = lib.mkIf readiness.ready {
            postgresql = {
              enable = true;
              package = pkgs.postgresql_17;
              dataDir = "/srv/personal/postgresql/17";
              enableTCPIP = false;
              ensureDatabases = [ "firefly-iii" ];
              ensureUsers = [
                {
                  name = "firefly-iii";
                  ensureDBOwnership = true;
                }
              ];
            };

            redis.servers.paperless = {
              save = [ ];
              appendOnly = false;
              settings.dir = lib.mkForce "/srv/personal/redis-paperless";
            };

            trilium-server = {
              enable = true;
              dataDir = "/srv/personal/trilium";
              host = localAddress;
              port = 8080;
              noAuthentication = false;
            };

            paperless = {
              enable = true;
              dataDir = "/srv/personal/paperless/data";
              mediaDir = "/srv/personal/paperless/media";
              consumptionDir = "/srv/paperless/consume";
              passwordFile = "/run/personal-stack/paperless-admin-password";
              address = localAddress;
              port = 28981;
              domain = paperlessName;
              database.createLocally = true;
              settings = {
                PAPERLESS_ADMIN_USER = owner;
                PAPERLESS_TASK_WORKERS = 1;
                PAPERLESS_URL = "https://${paperlessName}";
              };
            };

            firefly-iii = {
              enable = true;
              dataDir = "/srv/personal/firefly-iii";
              enableNginx = true;
              virtualHost = budgetName;
              poolConfig = {
                "pm.max_children" = 4;
                "pm.start_servers" = 1;
                "pm.min_spare_servers" = 1;
                "pm.max_spare_servers" = 2;
              };
              settings = {
                APP_ENV = "production";
                APP_KEY_FILE = "/run/personal-stack/firefly-app-key";
                STATIC_CRON_TOKEN_FILE = "/run/personal-stack/firefly-cron-token";
                DB_CONNECTION = "pgsql";
                DB_HOST = "/run/postgresql";
                DB_DATABASE = "firefly-iii";
                DB_USERNAME = "firefly-iii";
                TRUSTED_PROXIES = hostAddress;
              };
            };

            firefly-iii-data-importer = lib.mkIf readiness.importerReady {
              enable = true;
              dataDir = "/srv/personal/firefly-iii-data-importer";
              enableNginx = true;
              virtualHost = importerName;
              poolConfig = {
                "pm.max_children" = 2;
                "pm.start_servers" = 1;
                "pm.min_spare_servers" = 1;
                "pm.max_spare_servers" = 1;
              };
              settings = {
                APP_ENV = "production";
                FIREFLY_III_URL = "http://${budgetName}";
                VANITY_URL = "https://${budgetName}";
                FIREFLY_III_ACCESS_TOKEN_FILE = "/run/personal-stack/importer-access-token";
              };
            };

            open-webui = {
              enable = true;
              stateDir = "/srv/personal/open-webui";
              host = localAddress;
              port = 3000;
              openFirewall = false;
              environmentFile = "/run/personal-stack/open-webui.env";
              environment = {
                ENABLE_OLLAMA_API = "False";
                ENABLE_OPENAI_API = if llamaReady then "True" else "False";
                ENABLE_SIGNUP = "False";
                HF_HOME = "/srv/personal/open-webui/cache/huggingface";
                SENTENCE_TRANSFORMERS_HOME = "/srv/personal/open-webui/cache/sentence-transformers";
                TIKTOKEN_CACHE_DIR = "/srv/personal/open-webui/cache/tiktoken";
                WHISPER_MODEL_DIR = "/srv/personal/open-webui/cache/whisper";
                XDG_CACHE_HOME = "/srv/personal/open-webui/cache/xdg";
                WEBUI_ADMIN_EMAIL = readiness.openWebuiAdminEmail;
                WEBUI_ADMIN_NAME = owner;
                WEBUI_URL = "https://${chatName}";
              };
            };
          };

          systemd = {
            services = lib.mkIf readiness.ready (
              lib.mkMerge [
                {
                  personal-stack-version-gate = {
                    description = "Refuse unapproved personal application migrations";
                    before = map (unit: "${unit}.service") guardedServices;
                    requiredBy = map (unit: "${unit}.service") guardedServices;
                    unitConfig = {
                      RequiresMountsFor = [ "/srv/personal" ];
                      ConditionPathIsMountPoint = [ "/srv/personal" ];
                    };
                    serviceConfig = {
                      Type = "oneshot";
                      RemainAfterExit = true;
                    };
                    script = ''
                      set -eu
                      ${pkgs.diffutils}/bin/cmp --silent ${approvedVersionsFile} /srv/personal/approved-versions
                    '';
                  };

                  personal-stack-secrets = {
                    description = "Prepare owner-only personal state and credentials";
                    before = map (unit: "${unit}.service") guardedServices;
                    requiredBy = map (unit: "${unit}.service") guardedServices;
                    after = [ "systemd-tmpfiles-setup.service" ];
                    serviceConfig = {
                      Type = "oneshot";
                      RemainAfterExit = true;
                      RuntimeDirectory = "personal-stack";
                      # Application-owned 0400 files need a traversable shared
                      # parent; mode 0711 permits lookup but not enumeration.
                      RuntimeDirectoryMode = "0711";
                      UMask = "0077";
                      LoadCredential = [
                        (mkCredential "paperless-admin-password" "/run/owner-secrets/personal/${credentialBaseName secretFiles.paperlessAdminPassword}")
                        (mkCredential "firefly-app-key" "/run/owner-secrets/personal/${credentialBaseName secretFiles.fireflyAppKey}")
                        (mkCredential "firefly-cron-token" "/run/owner-secrets/personal/${credentialBaseName secretFiles.fireflyCronToken}")
                        (mkCredential "open-webui-secret-key" "/run/owner-secrets/personal/${credentialBaseName secretFiles.openWebuiSecretKey}")
                        (mkCredential "open-webui-admin-password" "/run/owner-secrets/personal/${credentialBaseName secretFiles.openWebuiAdminPassword}")
                      ]
                      ++ lib.optional readiness.importerReady (
                        mkCredential "importer-access-token" "/run/owner-secrets/personal/${credentialBaseName secretFiles.importerAccessToken}"
                      )
                      ++ lib.optional llamaReady (mkCredential "llama-api-key" llamaContainerFile);
                    };
                    script = ''
                      set -eu
                      # systemd-tmpfiles rejects service-owned children below
                      # the deliberately owner-owned bind root. Prepare the
                      # reviewed state paths only after the inner gates run.
                      ${pkgs.coreutils}/bin/install -d -m 0750 -o postgres -g postgres /srv/personal/postgresql/17
                      ${pkgs.coreutils}/bin/install -d -m 0750 -o trilium -g trilium /srv/personal/trilium
                      ${pkgs.coreutils}/bin/install -d -m 0750 -o paperless -g paperless /srv/personal/paperless
                      ${pkgs.coreutils}/bin/install -d -m 0710 -o firefly-iii -g nginx /srv/personal/firefly-iii
                      ${pkgs.coreutils}/bin/install -d -m 0700 -o firefly-iii-data-importer -g nginx /srv/personal/firefly-iii-data-importer
                      ${pkgs.coreutils}/bin/install -d -m 0700 -o open-webui -g open-webui /srv/personal/open-webui /srv/personal/open-webui/cache
                      ${pkgs.coreutils}/bin/install -d -m 0700 -o redis-paperless -g redis-paperless /srv/personal/redis-paperless
                      ${pkgs.coreutils}/bin/install -d -m 2770 -o paperless -g ${consumeGroup owner} /srv/paperless/consume
                      ${pkgs.coreutils}/bin/ln -sfn ${triliumConfigFile owner localAddress} /srv/personal/trilium/config.ini
                      one_line() {
                        test -s "$1"
                        newline_count="$(${pkgs.coreutils}/bin/tr -cd '\n' < "$1" | ${pkgs.coreutils}/bin/wc -c)"
                        test "$newline_count" -eq 0 || {
                          test "$newline_count" -eq 1
                          test -z "$(${pkgs.coreutils}/bin/tail -c 1 "$1")"
                        }
                        if ${pkgs.coreutils}/bin/tr -d '\n' < "$1" | ${pkgs.gnugrep}/bin/grep -q '[[:cntrl:]]'; then
                          echo "credential contains a control character: $1" >&2
                          return 1
                        fi
                      }
                      one_line "$CREDENTIALS_DIRECTORY/paperless-admin-password"
                      test "$(${pkgs.coreutils}/bin/wc -c < "$CREDENTIALS_DIRECTORY/paperless-admin-password")" -ge 20
                      ${pkgs.gnugrep}/bin/grep -Eq '^base64:[A-Za-z0-9+/]{43}=$' "$CREDENTIALS_DIRECTORY/firefly-app-key"
                      ${pkgs.gnugrep}/bin/grep -Eq '^[A-Za-z0-9_-]{32}$' "$CREDENTIALS_DIRECTORY/firefly-cron-token"
                      one_line "$CREDENTIALS_DIRECTORY/open-webui-secret-key"
                      test "$(${pkgs.coreutils}/bin/wc -c < "$CREDENTIALS_DIRECTORY/open-webui-secret-key")" -ge 32
                      one_line "$CREDENTIALS_DIRECTORY/open-webui-admin-password"
                      test "$(${pkgs.coreutils}/bin/wc -c < "$CREDENTIALS_DIRECTORY/open-webui-admin-password")" -ge 20
                      ${lib.optionalString readiness.importerReady ''
                        one_line "$CREDENTIALS_DIRECTORY/importer-access-token"
                        test "$(${pkgs.coreutils}/bin/wc -c < "$CREDENTIALS_DIRECTORY/importer-access-token")" -ge 32
                      ''}
                      ${lib.optionalString llamaReady ''
                        ${pkgs.gnugrep}/bin/grep -Eq '^[A-Za-z0-9_-]{32,}$' "$CREDENTIALS_DIRECTORY/llama-api-key"
                      ''}

                      install -m 0400 -o paperless -g paperless "$CREDENTIALS_DIRECTORY/paperless-admin-password" /run/personal-stack/paperless-admin-password
                      install -m 0400 -o firefly-iii -g nginx "$CREDENTIALS_DIRECTORY/firefly-app-key" /run/personal-stack/firefly-app-key
                      install -m 0400 -o firefly-iii -g nginx "$CREDENTIALS_DIRECTORY/firefly-cron-token" /run/personal-stack/firefly-cron-token
                      ${lib.optionalString readiness.importerReady ''
                        install -m 0400 -o firefly-iii-data-importer -g nginx "$CREDENTIALS_DIRECTORY/importer-access-token" /run/personal-stack/importer-access-token
                      ''}
                      {
                        printf 'WEBUI_SECRET_KEY=%s\n' "$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/open-webui-secret-key")"
                        printf 'WEBUI_ADMIN_PASSWORD=%s\n' "$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/open-webui-admin-password")"
                        ${lib.optionalString llamaReady ''
                          printf 'OPENAI_API_BASE_URLS=http://${hostAddress}:8081/v1\n'
                          printf 'OPENAI_API_KEYS=%s\n' "$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/llama-api-key")"
                        ''}
                      } > /run/personal-stack/open-webui.env
                      chown open-webui:open-webui /run/personal-stack/open-webui.env
                      chmod 0400 /run/personal-stack/open-webui.env
                    '';
                  };

                  open-webui.serviceConfig = {
                    DynamicUser = lib.mkForce false;
                    User = "open-webui";
                    Group = "open-webui";
                    CPUWeight = 50;
                    IOWeight = 50;
                    OOMScoreAdjust = 400;
                  };
                }
                (lib.genAttrs guardedServices (unit: {
                  requires = gateUnits;
                  after = gateUnits;
                }))
              ]
            );

            slices.system-paperless.sliceConfig = lib.mkIf readiness.ready {
              CPUWeight = 200;
              IOWeight = 200;
              MemoryAccounting = true;
            };
          };
        };

      autoStart = readiness.ready;
      ephemeral = true;
      restartIfChanged = false;
      privateNetwork = true;
      privateUsers = "identity";
      inherit hostAddress localAddress;
      bindMounts = {
        "/srv/personal" = {
          hostPath = ownerApps owner;
          isReadOnly = false;
        };
        "/srv/paperless/consume" = {
          hostPath = ownerConsume owner;
          isReadOnly = false;
        };
        "/run/owner-secrets" = {
          hostPath = ownerSecretRoot owner;
          isReadOnly = true;
        };
      };
      tmpfs = [
        "/srv/personal/open-webui/cache"
        "/tmp"
        "/var/tmp"
      ];
    };

  readyOwners = lib.filter (owner: cfg.owners.${owner}.readiness.ready) owners;
  importerReadyOwners = lib.filter (owner: cfg.owners.${owner}.readiness.importerReady) owners;
  anyReady = readyOwners != [ ];

  mkOwnerConfig =
    owner:
    let
      ownerCfg = cfg.owners.${owner};
      readiness = ownerCfg.readiness;
      baseFiles = requiredBaseFiles readiness;
      allFiles = baseFiles ++ [
        readiness.files.importerAccessToken
        readiness.files.importerProxyPassword
      ];
      hostCredentialFiles =
        baseFiles
        ++ lib.optionals readiness.importerReady [
          readiness.files.importerAccessToken
          readiness.files.importerProxyPassword
        ]
        ++ lib.optional (llamaReadyFor owner) (
          config.balaur.sharedServices.llama.readiness.ownerApiKeyFiles.${owner}
        );
      prepareHostInputs = ''
        set -eu
        test ! -L ${ownerHome owner}
        test ! -L ${ownerApps owner}
        test "$(${pkgs.coreutils}/bin/stat -Lc '%a:%U:%G' ${ownerHome owner})" = 700:${owner}:users
        test "$(${pkgs.coreutils}/bin/stat -Lc '%U:%G' ${ownerApps owner})" = ${owner}:users
        test -d ${ownerHome owner}/files
        test ! -L ${ownerHome owner}/files
        test "$(${pkgs.coreutils}/bin/stat -Lc '%a:%U:%G' ${ownerHome owner}/files)" = 700:${owner}:users
        test "$(${pkgs.coreutils}/bin/readlink -e ${ownerHome owner}/files)" = ${ownerHome owner}/files
        test "$(${pkgs.util-linux}/bin/findmnt -rn -T ${ownerHome owner}/files -o TARGET)" = ${ownerHome owner}
        test -f ${versionMarker owner}
        test ! -L ${versionMarker owner}
        test "$(${pkgs.coreutils}/bin/readlink -e ${versionMarker owner})" = ${versionMarker owner}
        ${pkgs.diffutils}/bin/cmp --silent ${approvedVersionsFile} ${versionMarker owner}
        test ! -L ${ownerSecretRoot owner}
        test "$(${pkgs.coreutils}/bin/readlink -e ${ownerSecretRoot owner})" = ${ownerSecretRoot owner}
        test "$(${pkgs.coreutils}/bin/stat -Lc '%a:%u:%g' ${ownerSecretRoot owner})" = 700:0:0
        ${lib.concatMapStringsSep "\n" (path: ''
          test -f ${path}
          test ! -L ${path}
          test "$(${pkgs.coreutils}/bin/readlink -e ${path})" = ${path}
          case "$(${pkgs.coreutils}/bin/stat -Lc '%a:%u:%g' ${path})" in
            400:0:0|600:0:0) ;;
            *) echo "unsafe owner runtime credential metadata: ${path}" >&2; exit 1 ;;
          esac
        '') hostCredentialFiles}
        if test -e ${ownerConsume owner} || test -L ${ownerConsume owner}; then
          test -d ${ownerConsume owner}
          test ! -L ${ownerConsume owner}
          test "$(${pkgs.coreutils}/bin/readlink -e ${ownerConsume owner})" = ${ownerConsume owner}
        fi
        install -d -m 2770 -o ${owner} -g ${consumeGroup owner} ${ownerConsume owner}
        test ! -L ${ownerConsume owner}
        test "$(${pkgs.coreutils}/bin/readlink -e ${ownerConsume owner})" = ${ownerConsume owner}
        test "$(${pkgs.util-linux}/bin/findmnt -rn -T ${ownerConsume owner} -o TARGET)" = ${ownerHome owner}
        # Boot-time tmpfiles may reset the ACL mask to the declared 0700
        # mode. Remove all access/default entries and reconstruct the exact
        # service traversal policy on every start.
        ${pkgs.acl}/bin/setfacl -bk ${ownerApps owner} ${ownerConsume owner}
        ${pkgs.coreutils}/bin/chmod 0700 ${ownerApps owner}
        ${pkgs.coreutils}/bin/chmod 2770 ${ownerConsume owner}
        ${pkgs.acl}/bin/setfacl -m u:0:rwx,u:71:--x,u:315:--x,u:900:--x,u:901:--x,u:902:--x,u:903:--x,u:904:--x ${ownerApps owner}
        ${pkgs.acl}/bin/setfacl -m u:0:rwx ${ownerConsume owner}
        ${pkgs.acl}/bin/getfacl -cpn ${ownerApps owner} | ${pkgs.diffutils}/bin/cmp --silent ${preparedOwnerAppsAcl} -
        ${pkgs.acl}/bin/getfacl -cpn ${ownerConsume owner} | ${pkgs.diffutils}/bin/cmp --silent ${preparedConsumeAcl} -
      '';
      storePathIsForbidden = path: path != null && lib.hasPrefix "/nix/store/" path;
    in
    {
      assertions = [
        {
          assertion =
            !readiness.ready
            || (readiness.openWebuiAdminEmail != null && lib.all (path: path != null) baseFiles);
          message = "${owner}'s personal stack readiness requires Paperless, Firefly, and closed Open WebUI bootstrap inputs";
        }
        {
          assertion = filesAreOwnerScoped owner allFiles && !lib.any storePathIsForbidden allFiles;
          message = "${owner}'s personal stack files must stay under that owner's exact runtime secret root and outside the Nix store";
        }
        {
          assertion =
            !readiness.importerReady
            || (
              readiness.ready
              && readiness.files.importerAccessToken != null
              && readiness.files.importerProxyPassword != null
            );
          message = "${owner}'s Data Importer requires the base stack, an owner-local Firefly token, and Caddy authentication";
        }
      ];

      warnings = lib.optional (!readiness.ready) ''
        DEPLOYMENT BLOCKER: ${owner}-personal is disabled. Supply the exact owner sops schema, fresh onboarding values, and ${versionMarker owner} before setting balaur.personalContainers.owners.${owner}.readiness.ready.
      '';

      users.groups.${consumeGroup owner}.gid = ownerCfg.consumeGroupId;
      users.users.${owner}.extraGroups = lib.mkAfter [ (consumeGroup owner) ];

      containers.${containerName owner} = mkContainerConfig owner ownerCfg;

      systemd.services = lib.mkIf readiness.ready {
        "personal-storage-${owner}" = {
          description = "Prepare ${owner}'s mounted personal application boundaries";
          before = [ "container@${containerName owner}.service" ];
          requiredBy = [ "container@${containerName owner}.service" ];
          unitConfig = {
            ConditionPathIsMountPoint = [
              (ownerApps owner)
              (ownerHome owner)
            ];
            RequiresMountsFor = [
              (ownerApps owner)
              (ownerHome owner)
            ];
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          # identity user namespacing isolates capabilities but preserves
          # numeric IDs. Exact ACLs grant container root (UID 0) initialization
          # access and only traversal to the fixed application UIDs; the host
          # `users` group retains no access.
          script = prepareHostInputs;
        };

        "container@${containerName owner}" = {
          requires = [ "personal-storage-${owner}.service" ];
          after = [ "personal-storage-${owner}.service" ];
          unitConfig.ConditionPathIsMountPoint = [
            (ownerApps owner)
            (ownerHome owner)
          ];
          preStart = lib.mkBefore prepareHostInputs;
          serviceConfig = {
            CPUWeight = 100;
            IOWeight = 100;
            MemoryAccounting = true;
            ManagedOOMMemoryPressure = "kill";
            ManagedOOMMemoryPressureLimit = "80%";
          };
        };
      };

      services.caddy.virtualHosts = lib.optionalAttrs readiness.importerReady {
        "importer.${owner}.home.arpa".extraConfig = lib.mkBefore ''
          import /run/caddy-importer-auth/${owner}.caddy
        '';
      };

      balaur.ingress.reverseProxies = lib.mkIf readiness.ready (
        {
          "notes.${owner}.home.arpa".backend = {
            host = ownerCfg.localAddress;
            port = 8080;
          };
          "paperless.${owner}.home.arpa".backend = {
            host = ownerCfg.localAddress;
            port = 28981;
          };
          "budget.${owner}.home.arpa".backend = {
            host = ownerCfg.localAddress;
            port = 80;
          };
          "chat.${owner}.home.arpa".backend = {
            host = ownerCfg.localAddress;
            port = 3000;
          };
        }
        // lib.optionalAttrs readiness.importerReady {
          "importer.${owner}.home.arpa".backend = {
            host = ownerCfg.localAddress;
            port = 80;
          };
        }
      );
    };

  mkLlamaForwarder =
    owner:
    let
      ownerCfg = cfg.owners.${owner};
      serviceName = "llama-forward-${owner}";
    in
    {
      systemd.sockets.${serviceName} = {
        description = "${owner}-only private llama forwarder";
        wantedBy = [ "sockets.target" ];
        socketConfig = {
          ListenStream = "${ownerCfg.hostAddress}:8081";
          FreeBind = true;
          Service = "${serviceName}.service";
        };
      };
      systemd.services.${serviceName} = {
        description = "Forward only ${owner}'s container to loopback llama.cpp";
        requires = [ "llama-router.service" ];
        after = [ "llama-router.service" ];
        serviceConfig = {
          ExecStart = "${config.systemd.package}/lib/systemd/systemd-socket-proxyd 127.0.0.1:8081";
          PrivateTmp = true;
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_UNIX"
          ];
        };
      };
    };
in
{
  options.balaur.personalContainers = {
    owners = lib.mkOption {
      type = lib.types.attrsOf ownerType;
      default = {
        alex = { };
        andreea = { };
      };
      description = "Fixed owner-separated personal container policies and human readiness gates.";
    };
    approvedVersions = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = approvedVersions;
      description = "Versions requiring an exact protected runtime marker before any app can start.";
    };
    egressInterface = lib.mkOption {
      type = lib.types.str;
      default = "enp100s0";
      description = "Reviewed household uplink used for narrowly allowed personal-container NAT.";
    };
    egressResolver = lib.mkOption {
      type = lib.types.strMatching "^192\\.168\\.[0-9]{1,3}\\.[0-9]{1,3}$";
      default = config.balaur.network.routerAddress;
      description = "Router DNS address reachable through the narrow container egress policy.";
    };
  };

  config = lib.mkMerge (
    [
      {
        assertions = [
          {
            assertion = builtins.attrNames cfg.owners == owners;
            message = "Personal containers are fixed to exactly Alex and Andreea";
          }
          {
            assertion =
              cfg.owners.alex.hostAddress != cfg.owners.andreea.hostAddress
              && cfg.owners.alex.localAddress != cfg.owners.andreea.localAddress;
            message = "Owner containers must retain distinct point-to-point addresses";
          }
          {
            assertion = cfg.owners.alex.consumeGroupId != cfg.owners.andreea.consumeGroupId;
            message = "Owner Paperless consume groups must not share a numeric GID";
          }
        ];

        systemd.services.caddy = lib.mkIf (importerReadyOwners != [ ]) {
          requires = map (owner: "personal-storage-${owner}.service") importerReadyOwners;
          after = map (owner: "personal-storage-${owner}.service") importerReadyOwners;
          preStart = lib.mkAfter ''
            set -eu
            ${lib.concatMapStringsSep "\n" (owner: ''
              password="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/importer-${owner}-password")"
              test "$(${pkgs.coreutils}/bin/printf '%s' "$password" | ${pkgs.coreutils}/bin/wc -l)" -eq 0
              test "$(${pkgs.coreutils}/bin/printf '%s' "$password" | ${pkgs.coreutils}/bin/wc -c)" -ge 20
              hash="$(${pkgs.coreutils}/bin/printf '%s\n' "$password" | ${config.services.caddy.package}/bin/caddy hash-password --algorithm bcrypt)"
              ${pkgs.coreutils}/bin/printf 'basic_auth {\n  ${owner} %s\n}\n' "$hash" > /run/caddy-importer-auth/${owner}.caddy
              chmod 0600 /run/caddy-importer-auth/${owner}.caddy
              unset password hash
            '') importerReadyOwners}
          '';
          serviceConfig = {
            RuntimeDirectory = "caddy-importer-auth";
            RuntimeDirectoryMode = "0700";
            LoadCredential = map (
              owner: "importer-${owner}-password:${cfg.owners.${owner}.readiness.files.importerProxyPassword}"
            ) importerReadyOwners;
          };
        };

        networking = lib.mkIf anyReady {
          nat = {
            enable = true;
            externalInterface = cfg.egressInterface;
            internalIPs = map (owner: "${cfg.owners.${owner}.localAddress}/32") readyOwners;
          };
          firewall = {
            extraCommands = ''
              iptables -N balaur-personal-input 2>/dev/null || iptables -F balaur-personal-input
              iptables -N balaur-personal-forward 2>/dev/null || iptables -F balaur-personal-forward
              iptables -C INPUT -j balaur-personal-input 2>/dev/null || iptables -I INPUT 1 -j balaur-personal-input
              iptables -C FORWARD -j balaur-personal-forward 2>/dev/null || iptables -I FORWARD 1 -j balaur-personal-forward
              iptables -A balaur-personal-input -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
              iptables -A balaur-personal-forward -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
              ${lib.concatMapStringsSep "\n" (
                owner:
                let
                  ownerCfg = cfg.owners.${owner};
                in
                ''
                  iptables -A balaur-personal-input -i ${hostInterfacePattern owner} ! -s ${ownerCfg.localAddress} -j DROP
                  ${lib.optionalString (llamaReadyFor owner) ''
                    iptables -A balaur-personal-input -i ${hostInterfacePattern owner} -s ${ownerCfg.localAddress} -d ${ownerCfg.hostAddress} -p tcp --dport 8081 -j ACCEPT
                  ''}
                  iptables -A balaur-personal-input -i ${hostInterfacePattern owner} -j DROP
                  iptables -A balaur-personal-forward -i ${hostInterfacePattern owner} ! -s ${ownerCfg.localAddress} -j DROP
                  iptables -A balaur-personal-forward -s ${ownerCfg.localAddress} -d ${cfg.egressResolver} -p udp --dport 53 -j ACCEPT
                  iptables -A balaur-personal-forward -s ${ownerCfg.localAddress} -d ${cfg.egressResolver} -p tcp --dport 53 -j ACCEPT
                  iptables -A balaur-personal-forward -s ${ownerCfg.localAddress} -d 10.0.0.0/8 -j REJECT
                  iptables -A balaur-personal-forward -s ${ownerCfg.localAddress} -d 172.16.0.0/12 -j REJECT
                  iptables -A balaur-personal-forward -s ${ownerCfg.localAddress} -d 192.168.0.0/16 -j REJECT
                  iptables -A balaur-personal-forward -s ${ownerCfg.localAddress} -o ${cfg.egressInterface} -p tcp --dport 443 -j ACCEPT
                  iptables -A balaur-personal-forward -s ${ownerCfg.localAddress} -o ${cfg.egressInterface} -p udp --dport 123 -j ACCEPT
                  iptables -A balaur-personal-forward -s ${ownerCfg.localAddress} -j REJECT
                  iptables -A balaur-personal-forward -d ${ownerCfg.localAddress} -j REJECT
                ''
              ) readyOwners}
              iptables -A balaur-personal-input -j RETURN
              iptables -A balaur-personal-forward -j RETURN
            '';
            extraStopCommands = ''
              iptables -D INPUT -j balaur-personal-input 2>/dev/null || true
              iptables -D FORWARD -j balaur-personal-forward 2>/dev/null || true
              iptables -F balaur-personal-input 2>/dev/null || true
              iptables -F balaur-personal-forward 2>/dev/null || true
              iptables -X balaur-personal-input 2>/dev/null || true
              iptables -X balaur-personal-forward 2>/dev/null || true
            '';
          };
        };
      }
    ]
    ++ map (owner: mkOwnerConfig owner) owners
    ++ map (owner: lib.mkIf (llamaReadyFor owner) (mkLlamaForwarder owner)) owners
  );
}
