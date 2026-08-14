{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.balaur.network;
  ingress = config.balaur.ingress;
  samba = config.balaur.samba;

  householdNames = [
    "balaur.home.arpa"
    "notes.alex.home.arpa"
    "paperless.alex.home.arpa"
    "budget.alex.home.arpa"
    "chat.alex.home.arpa"
    "notes.andreea.home.arpa"
    "paperless.andreea.home.arpa"
    "budget.andreea.home.arpa"
    "chat.andreea.home.arpa"
    "home-assistant.home.arpa"
    "jellyfin.home.arpa"
    "downloads.home.arpa"
  ];

  zoneFile = pkgs.writeText "home.arpa.zone" ''
    $ORIGIN home.arpa.
    $TTL 300
    @ IN SOA balaur.home.arpa. hostmaster.home.arpa. (
      1 3600 900 604800 300
    )
    @ IN NS balaur.home.arpa.
    ${lib.concatMapStringsSep "\n" (name: "${name}. IN A ${cfg.serverAddress}") householdNames}
  '';

  privateBackendHost = lib.types.strMatching (
    "^(127\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}"
    + "|10\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}"
    + "|192\\.168\\.[0-9]{1,3}\\.[0-9]{1,3}"
    + "|172\\.(1[6-9]|2[0-9]|3[01])\\.[0-9]{1,3}\\.[0-9]{1,3})$"
  );

  reverseProxyType = lib.types.submodule {
    options.backend = {
      host = lib.mkOption {
        type = privateBackendHost;
        description = "Loopback or RFC1918 address of the private backend.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        description = "Private backend TCP port; it is never opened by this module.";
      };
    };
  };

  mkProxyVirtualHost =
    name: route:
    lib.nameValuePair name {
      hostName = name;
      listenAddresses = [ cfg.serverAddress ];
      logFormat = null;
      extraConfig = ''
        tls internal
        reverse_proxy http://${route.backend.host}:${toString route.backend.port}
      '';
    };

  proxyVirtualHosts = lib.mapAttrs' mkProxyVirtualHost ingress.reverseProxies;
  sambaCredentialRoot = "/run/balaur-secrets/host/samba";
in
{
  options = {
    balaur.network = {
      trustedInterfaces = lib.mkOption {
        type = lib.types.nonEmptyListOf (lib.types.strMatching "^[a-zA-Z0-9_.:-]+$");
        default = [
          "enp100s0"
          "wlp98s0"
        ];
        description = ''
          Physical LAN interfaces trusted for household ingress. Router-provided
          WireGuard reaches these interfaces through its intranet/NAT path.
        '';
      };

      serverAddress = lib.mkOption {
        type = lib.types.strMatching "^192\\.168\\.[0-9]{1,3}\\.[0-9]{1,3}$";
        default = "192.168.50.2";
        description = "Observed router-reserved private address used by DNS and ingress listeners.";
      };

      routerAddress = lib.mkOption {
        type = lib.types.strMatching "^192\\.168\\.[0-9]{1,3}\\.[0-9]{1,3}$";
        default = "192.168.50.1";
        description = "ASUS LAN address used as CoreDNS's sole forwarding resolver.";
      };

      householdNames = lib.mkOption {
        type = lib.types.listOf (lib.types.strMatching "^[a-z0-9.-]+\\.home\\.arpa$");
        readOnly = true;
        default = householdNames;
        description = "Exact private DNS allowlist. Every name is authoritative at the server address.";
      };
    };

    balaur.ingress.reverseProxies = lib.mkOption {
      type = lib.types.attrsOf reverseProxyType;
      default = { };
      description = ''
        Typed registration seam for later service modules. Attribute names must
        be approved household DNS names and backends must remain private. Merely
        registering a route never opens the backend port in the firewall.
      '';
    };

    balaur.samba.credentials = {
      ready = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Human-controlled credential gate. Keep false until both runtime files
          are supplied by real sops-nix secrets. When false, smbd and TCP 445
          remain disabled even though the hardened share policy evaluates.
        '';
      };

      passwordFiles = {
        alex = lib.mkOption {
          type = lib.types.nullOr (lib.types.strMatching "^/run/balaur-secrets/host/samba/[a-zA-Z0-9._-]+$");
          default = null;
          description = "Runtime-only file containing Alex's Samba password.";
        };
        andreea = lib.mkOption {
          type = lib.types.nullOr (lib.types.strMatching "^/run/balaur-secrets/host/samba/[a-zA-Z0-9._-]+$");
          default = null;
          description = "Runtime-only file containing Andreea's Samba password.";
        };
      };
    };
  };

  config = {
    assertions = [
      {
        assertion =
          builtins.attrNames ingress.reverseProxies
          == lib.intersectLists householdNames (builtins.attrNames ingress.reverseProxies);
        message = "Caddy reverse proxies may register only exact approved home.arpa names";
      }
      {
        assertion = !(ingress.reverseProxies ? "balaur.home.arpa");
        message = "balaur.home.arpa is reserved for the host health endpoint";
      }
      {
        assertion =
          !samba.credentials.ready
          || (
            samba.credentials.passwordFiles.alex != null
            && samba.credentials.passwordFiles.andreea != null
            && lib.hasPrefix "${sambaCredentialRoot}/" samba.credentials.passwordFiles.alex
            && lib.hasPrefix "${sambaCredentialRoot}/" samba.credentials.passwordFiles.andreea
            && samba.credentials.passwordFiles.alex != samba.credentials.passwordFiles.andreea
          );
        message = "Enabling Samba requires distinct Alex and Andreea runtime password files under the host Samba secret root";
      }
    ];

    warnings = lib.optional (!samba.credentials.ready) ''
      DEPLOYMENT BLOCKER: Samba is fail-closed because balaur.samba.credentials.ready is false. Create real sops-backed runtime password files for both owners before enabling it; do not put passwords in Nix.
    '';

    users.groups.media = { };
    users.users.alex.extraGroups = lib.mkAfter [ "media" ];
    users.users.andreea.extraGroups = lib.mkAfter [ "media" ];

    systemd.tmpfiles.rules = [
      "d /home/alex/files 0700 alex users -"
      "d /home/andreea/files 0700 andreea users -"
      "d /srv/media 2750 alex media -"
    ];

    services.coredns = {
      enable = true;
      config = ''
        home.arpa:53 {
          bind ${cfg.serverAddress}
          file ${zoneFile} home.arpa
          cache 300
          errors
        }

        .:53 {
          bind ${cfg.serverAddress}
          forward . ${cfg.routerAddress}
          cache 300
          errors
        }
      '';
    };

    services.caddy = {
      enable = true;
      enableReload = false;
      openFirewall = false;
      globalConfig = ''
        admin off
        auto_https disable_redirects
        skip_install_trust
        servers {
          protocols h1 h2
        }
      '';
      virtualHosts = {
        "https://balaur.home.arpa" = {
          hostName = "https://balaur.home.arpa";
          listenAddresses = [ cfg.serverAddress ];
          logFormat = null;
          extraConfig = ''
            tls internal
            @health path /health
            respond @health "balaur ok" 200
            respond "not found" 404
          '';
        };
        "http://balaur.home.arpa" = {
          hostName = "http://balaur.home.arpa";
          listenAddresses = [ cfg.serverAddress ];
          logFormat = null;
          extraConfig = ''
            redir https://balaur.home.arpa{uri} permanent
          '';
        };
      }
      // proxyVirtualHosts;
    };

    services.samba = {
      enable = samba.credentials.ready;
      openFirewall = false;
      nmbd.enable = false;
      winbindd.enable = false;
      usershares.enable = false;
      settings = {
        global = {
          security = "user";
          "server role" = "standalone server";
          "server min protocol" = "SMB2";
          "server max protocol" = "SMB3";
          "smb ports" = "445";
          "disable netbios" = "yes";
          interfaces = lib.concatStringsSep " " cfg.trustedInterfaces;
          "bind interfaces only" = "yes";
          "map to guest" = "Never";
          "restrict anonymous" = "2";
          "usershare allow guests" = "no";
          "load printers" = "no";
          printing = "bsd";
          "printcap name" = "/dev/null";
          "dns proxy" = "no";
          "invalid users" = [ "root" ];
        };
        alex = {
          path = "/home/alex/files";
          "valid users" = [ "alex" ];
          "guest ok" = "no";
          browseable = "yes";
          "read only" = "no";
        };
        andreea = {
          path = "/home/andreea/files";
          "valid users" = [ "andreea" ];
          "guest ok" = "no";
          browseable = "yes";
          "read only" = "no";
        };
        media = {
          path = "/srv/media";
          "valid users" = [
            "alex"
            "andreea"
          ];
          "write list" = [ "alex" ];
          "guest ok" = "no";
          browseable = "yes";
          "read only" = "yes";
          "force group" = "media";
        };
      };
    };

    systemd.services = {
      coredns = {
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
      };
    }
    // lib.optionalAttrs samba.credentials.ready {
      samba-credentials = {
        description = "Provision Samba passdb from runtime credentials";
        before = [ "samba-smbd.service" ];
        requiredBy = [ "samba-smbd.service" ];
        after = [ "systemd-tmpfiles-setup.service" ];
        unitConfig.RequiresMountsFor = "/var/lib/samba";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
          LoadCredential = [
            "alex-password:${samba.credentials.passwordFiles.alex}"
            "andreea-password:${samba.credentials.passwordFiles.andreea}"
          ];
        };
        script = ''
          set -eu
          provision() {
            user="$1"
            credential="$2"
            password="$(${pkgs.coreutils}/bin/cat "$CREDENTIALS_DIRECTORY/$credential")"
            test -n "$password"
            ${pkgs.coreutils}/bin/printf '%s\n%s\n' "$password" "$password" \
              | ${config.services.samba.package}/bin/smbpasswd -s -a "$user"
            unset password
          }
          provision alex alex-password
          provision andreea andreea-password
        '';
      };

      samba-smbd = {
        requires = [ "samba-credentials.service" ];
        after = [ "samba-credentials.service" ];
        unitConfig.RequiresMountsFor = [
          "/home/alex/files"
          "/home/andreea/files"
          "/srv/media"
        ];
      };
    };

    networking.firewall = {
      allowedTCPPorts = [ ];
      allowedUDPPorts = [ ];
      interfaces = lib.genAttrs cfg.trustedInterfaces (_: {
        allowedTCPPorts = [
          22
          53
          80
          443
        ]
        ++ lib.optional samba.credentials.ready 445;
        allowedUDPPorts = [ 53 ];
      });
    };
  };
}
