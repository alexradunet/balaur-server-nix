{ config, pkgs }:

let
  inherit (pkgs) lib;
  policy = config.balaur.secrets;
  secretDirectoryEntries = builtins.readDir ../secrets;
  expectedPolicies = {
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
  requiredTmpfilesRules = [
    "d /var/lib/sops-nix 0700 root root -"
    "d /run/balaur-secrets 0700 root root -"
    "d /run/balaur-secrets/owners 0700 root root -"
    "d /run/balaur-secrets/host 0700 root root -"
    "d /run/balaur-secrets/owners/alex 0700 root root -"
    "d /run/balaur-secrets/owners/andreea 0700 root root -"
  ];
  assertions = [
    {
      assertion =
        config.sops.age.keyFile == "/var/lib/sops-nix/key.txt"
        && !config.sops.age.generateKey
        && config.sops.age.sshKeyPaths == [ ]
        && config.sops.gnupg.home == null
        && config.sops.gnupg.sshKeyPaths == [ ];
      message = "sops-nix must use only the human-installed dedicated age identity, never SSH keys";
    }
    {
      assertion =
        policy.ageKeyFile == config.sops.age.keyFile
        && policy.runtimeRoot == "/run/balaur-secrets"
        && policy.policies == expectedPolicies
        && policy.policies.alex.runtimeDirectory != policy.policies.andreea.runtimeDirectory
        && policy.policies.host.runtimeDirectory != policy.policies.alex.runtimeDirectory
        && policy.policies.host.runtimeDirectory != policy.policies.andreea.runtimeDirectory;
      message = "typed host, Alex, and Andreea secret policy roots must be explicit and distinct";
    }
    {
      assertion = lib.all (rule: builtins.elem rule config.systemd.tmpfiles.rules) requiredTmpfilesRules;
      message = "age-key state and all secret policy runtime roots must remain root-only";
    }
    {
      assertion =
        config.sops.secrets == { }
        && config.sops.templates == { }
        && config.sops.placeholder == { }
        &&
          secretDirectoryEntries == {
            "README.md" = "regular";
          };
      message = "no encrypted payload, decrypted value, placeholder, or secret declaration may exist before human onboarding";
    }
    {
      assertion = config.containers == { };
      message = "no decrypted secret directory may be exposed globally to containers before issue 12";
    }
    {
      assertion =
        config.balaur.access.bootstrapPasswordlessSudo
        && config.users.users.alex.hashedPasswordFile == null;
      message = "Alex's password hash and final sudo hardening must remain visibly unresolved";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur secret-boundary invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-secret-boundary-tests" { } ''
    mkdir -p "$out"
    printf '%s\n' 'Secret wiring is fail-closed pending human key and password onboarding.' > "$out/result"
  ''
