{
  config,
  lib,
  ...
}:

let
  cfg = config.balaur.secrets;

  policyType = lib.types.submodule {
    options = {
      scope = lib.mkOption {
        type = lib.types.enum [
          "host"
          "owner"
        ];
        description = "Authority boundary represented by this runtime root.";
      };

      owner = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "alex"
            "andreea"
          ]
        );
        description = "Owner represented by an owner policy, or null for the host policy.";
      };

      runtimeDirectory = lib.mkOption {
        type = lib.types.strMatching "^/run/balaur-secrets(/[a-z]+)+$";
        description = "Root-only host runtime directory for this policy's decrypted values.";
      };

      directoryMode = lib.mkOption {
        type = lib.types.strMatching "0[0-7]{3}";
        description = "tmpfiles mode for the policy runtime directory.";
      };
    };
  };

  policyRoots = map (policy: policy.runtimeDirectory) (builtins.attrValues cfg.policies);
  declaredRuntimePaths =
    map (secret: secret.path) (builtins.attrValues config.sops.secrets)
    ++ map (template: template.path) (builtins.attrValues config.sops.templates);
  isWithin = root: path: path == root || lib.hasPrefix "${root}/" path;
  containerSecretBindsAreScoped = lib.all (
    containerName:
    let
      container = config.containers.${containerName};
      expectedOwnerRoot =
        if
          builtins.hasAttr containerName cfg.policies && cfg.policies.${containerName}.scope == "owner"
        then
          cfg.policies.${containerName}.runtimeDirectory
        else
          null;
    in
    lib.all (
      mount:
      let
        source = mount.hostPath;
      in
      source == null
      || (
        !isWithin (builtins.dirOf cfg.ageKeyFile) source
        && !isWithin "/run/secrets" source
        && (!isWithin cfg.runtimeRoot source || (source == expectedOwnerRoot && mount.isReadOnly))
      )
    ) (builtins.attrValues container.bindMounts)
  ) (builtins.attrNames config.containers);
in
{
  options.balaur.secrets = {
    ageKeyFile = lib.mkOption {
      type = lib.types.strMatching "^/var/lib/sops-nix/[a-zA-Z0-9._-]+$";
      readOnly = true;
      default = "/var/lib/sops-nix/key.txt";
      description = "Dedicated, human-installed age identity used by sops-nix; never an SSH host key.";
    };

    runtimeRoot = lib.mkOption {
      type = lib.types.strMatching "^/run/[a-zA-Z0-9._-]+$";
      readOnly = true;
      default = "/run/balaur-secrets";
      description = "Root-only parent for policy-separated decrypted secret directories.";
    };

    policies = lib.mkOption {
      type = lib.types.attrsOf policyType;
      readOnly = true;
      default = {
        host = {
          scope = "host";
          owner = null;
          runtimeDirectory = "/run/balaur-secrets/host";
          directoryMode = "0700";
        };
        alex = {
          scope = "owner";
          owner = "alex";
          runtimeDirectory = "/run/balaur-secrets/owners/alex";
          directoryMode = "0700";
        };
        andreea = {
          scope = "owner";
          owner = "andreea";
          runtimeDirectory = "/run/balaur-secrets/owners/andreea";
          directoryMode = "0700";
        };
      };
      description = ''
        Typed host and owner policy roots. Later modules must place each sops
        secret below exactly one of these roots and bind only an owner's exact
        root into that owner's container.
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion =
          cfg.policies.host.scope == "host"
          && cfg.policies.host.owner == null
          && cfg.policies.alex.scope == "owner"
          && cfg.policies.alex.owner == "alex"
          && cfg.policies.andreea.scope == "owner"
          && cfg.policies.andreea.owner == "andreea";
        message = "Balaur secret policies must preserve the host, Alex, and Andreea authority boundaries";
      }
      {
        assertion = builtins.length policyRoots == builtins.length (lib.unique policyRoots);
        message = "Balaur host and owner secret runtime roots must remain distinct";
      }
      {
        assertion = lib.all (
          path: lib.any (root: lib.hasPrefix "${root}/" path) policyRoots
        ) declaredRuntimePaths;
        message = "Every sops secret/template must use an explicit Balaur host or owner policy runtime root";
      }
      {
        assertion = containerSecretBindsAreScoped;
        message = "Containers may receive only their exact read-only owner secret root, never the age key, host/other-owner secrets, or a global decrypted-secret root";
      }
    ];

    # Deliberately use one separately generated age identity. Importing SSH host
    # keys (or generating a replacement identity during activation) would make
    # recovery and recipient authority implicit.
    sops = {
      age = {
        keyFile = cfg.ageKeyFile;
        generateKey = false;
        sshKeyPaths = lib.mkForce [ ];
      };
      gnupg = {
        home = null;
        sshKeyPaths = lib.mkForce [ ];
      };
    };

    # These directories contain no values yet. Secret declarations are added
    # only after their encrypted files and human-owned recipient exist.
    systemd.tmpfiles.rules = [
      "d /var/lib/sops-nix 0700 root root -"
      "d ${cfg.runtimeRoot} 0700 root root -"
      "d ${cfg.runtimeRoot}/owners 0700 root root -"
    ]
    ++ map (policy: "d ${policy.runtimeDirectory} ${policy.directoryMode} root root -") (
      builtins.attrValues cfg.policies
    );
  };
}
