{ pkgs, ... }:

{
  # Preserve the UIDs/GIDs already assigned on this installed host. Nixarr's
  # fixed IDs are useful for fresh installs but would orphan existing state and
  # media files during an in-place migration.
  util-nixarr.globals = {
    uids = builtins.mapAttrs (_name: _uid: pkgs.lib.mkForce null) {
      jellyfin = null;
      prowlarr = null;
      sonarr = null;
      radarr = null;
      lidarr = null;
      qbittorrent = null;
    };
    gids = {
      media = pkgs.lib.mkForce null;
      prowlarr = pkgs.lib.mkForce null;
    };
  };

  # Nixarr owns the media-service users, permissions, state locations, and VPN
  # confinement. Keep the existing state paths so this is an in-place migration.
  nixarr = {
    enable = true;
    mediaDir = "/srv/media/ssd0";
    stateDir = "/srv/app-data";

    vpn = {
      enable = true;
      wgConf = "/srv/secrets/protonvpn.conf";
    };

    jellyfin.enable = true;
    prowlarr = {
      enable = true;
      # Keep every supported Arr application linked with Full Sync.
      settings-sync.enable-nixarr-apps = true;
    };
    sonarr.enable = true;
    radarr.enable = true;
    lidarr.enable = true;

    qbittorrent = {
      enable = true;
      vpn.enable = true;
      # Keep the native Web UI/API so the existing Arr download-client
      # configuration remains valid through the host-side proxy below.
      qui.enable = false;
      webuiPort = 8082;
      peerPort = 6881;

      # Match the existing two-disk layout rather than Nixarr's single-disk
      # defaults. Existing category-specific paths remain in qBittorrent state.
      extraConfig = {
        BitTorrent = {
          "Session\\DefaultSavePath" = "/srv/media/ssd0/downloads/complete";
          "Session\\TempPath" = "/srv/media/ssd0/downloads/incomplete";
        };
        Preferences = {
          "Downloads\\SavePath" = "/srv/media/ssd0/downloads/complete";
          "Downloads\\TempPath" = "/srv/media/ssd0/downloads/incomplete";
          # Do not inherit Nixarr's VPN-subnet authentication bypass: every
          # LAN request arrives through the namespace bridge/proxy.
          "WebUI\\AuthSubnetWhitelistEnabled" = false;
          "WebUI\\CSRFProtection" = true;
          "WebUI\\LocalHostAuth" = true;
        };
      };
    };
  };

  # Nixarr's Jellyfin layout puts data below stateDir/data. Override only this
  # path to preserve the existing database during the in-place migration.
  services.jellyfin.dataDir = pkgs.lib.mkForce "/srv/app-data/jellyfin";

  # Nixarr's settings synchronization uses each application's loopback API.
  # Browser authentication remains required for clients arriving from the LAN.
  services.prowlarr.settings.auth.required = "DisabledForLocalAddresses";
  services.sonarr.settings.auth.required = "DisabledForLocalAddresses";
  services.radarr.settings.auth.required = "DisabledForLocalAddresses";
  services.lidarr.settings.auth.required = "DisabledForLocalAddresses";

  services.seerr = {
    enable = true;
    openFirewall = false;
    port = 5055;
    configDir = "/srv/app-data/seerr";
  };

  # The upstream module uses DynamicUser for /var/lib/seerr. A static account
  # lets Seerr keep its database on the mirrored application filesystem.
  users.groups.seerr = { };
  users.users.seerr = {
    isSystemUser = true;
    group = "seerr";
    home = "/srv/app-data/seerr";
  };
  systemd.services.seerr.serviceConfig = {
    DynamicUser = pkgs.lib.mkForce false;
    User = "seerr";
    Group = "seerr";
    ReadWritePaths = [ "/srv/app-data/seerr" ];
  };
  # Nixarr supplies a static Prowlarr account, but the upstream NixOS service
  # still enables DynamicUser. Disable it so systemd can reuse the existing
  # real /var/lib/prowlarr directory instead of requiring a private-state symlink.
  systemd.services.prowlarr.serviceConfig.DynamicUser = pkgs.lib.mkForce false;

  # The storage filesystems are intentionally nofail so the host can still boot
  # degraded. Stop only the affected media services rather than letting them use
  # empty mount points on the OS filesystem.
  systemd.services.jellyfin.unitConfig.RequiresMountsFor = pkgs.lib.mkAfter [
    "/srv/app-data"
    "/srv/media/ssd0"
    "/srv/media/ssd1"
  ];
  systemd.services.prowlarr.unitConfig.RequiresMountsFor = pkgs.lib.mkAfter [ "/srv/app-data" ];
  systemd.services.sonarr.unitConfig.RequiresMountsFor = pkgs.lib.mkAfter [
    "/srv/app-data"
    "/srv/media/ssd1"
  ];
  systemd.services.radarr.unitConfig.RequiresMountsFor = pkgs.lib.mkAfter [
    "/srv/app-data"
    "/srv/media/ssd0"
  ];
  systemd.services.lidarr.unitConfig.RequiresMountsFor = pkgs.lib.mkAfter [
    "/srv/app-data"
    "/srv/media/ssd1"
  ];
  systemd.services.qbittorrent.unitConfig.RequiresMountsFor = pkgs.lib.mkAfter [
    "/srv/app-data"
    "/srv/media/ssd0"
    "/srv/media/ssd1"
  ];

  # Keep completed files and directories writable by the Arr services, which
  # need to import and clean up qBittorrent's category-specific downloads.
  systemd.services.qbittorrent.serviceConfig.UMask = pkgs.lib.mkForce "0002";

  # NixOS regenerates qBittorrent.conf on every service start. Inject a stable,
  # host-local Web UI password afterward so reboots do not invalidate Arr clients.
  systemd.services.qbittorrent.serviceConfig = {
    Restart = "on-failure";
    RestartSec = 10;
    ExecStartPre = pkgs.lib.mkAfter [
      "+${pkgs.writeShellScript "qbittorrent-webui-password" ''
      set -euo pipefail
      secret=/srv/secrets/qbittorrent-webui-password
      config=/srv/app-data/qbittorrent/qBittorrent/config/qBittorrent.conf

      if [[ ! -s "$secret" ]]; then
        umask 0077
        ${pkgs.openssl}/bin/openssl rand -base64 24 | ${pkgs.coreutils}/bin/tr -d '\n' > "$secret"
      fi
      ${pkgs.coreutils}/bin/chown root:root "$secret"
      ${pkgs.coreutils}/bin/chmod 0600 "$secret"

      password_hash="$(${pkgs.nodejs}/bin/node - "$secret" <<'EOF'
      const crypto = require("crypto");
      const fs = require("fs");
      const password = fs.readFileSync(process.argv[2], "utf8").trim();
      const salt = crypto.randomBytes(16);
      const hash = crypto.pbkdf2Sync(password, salt, 100000, 64, "sha512");
      process.stdout.write(`@ByteArray(''${salt.toString("base64")}:''${hash.toString("base64")})`);
      EOF
      )"

      ${pkgs.gawk}/bin/awk -v value="$password_hash" '
        $0 == "[Preferences]" {
          print
          print "WebUI\\Password_PBKDF2=" value
          next
        }
        $0 !~ /^WebUI\\Password_PBKDF2=/ { print }
      ' "$config" > "$config.tmp"
      ${pkgs.coreutils}/bin/chown qbittorrent:media "$config.tmp"
      ${pkgs.coreutils}/bin/chmod 0600 "$config.tmp"
      ${pkgs.coreutils}/bin/mv "$config.tmp" "$config"
      ''}"
    ];
  };

  # Converge every Arr download client on the host-local password. The APIs
  # mask stored passwords, so the service safely overwrites the field at boot
  # and restarts qBittorrent once to clear any shared proxy-IP authentication ban.
  systemd.services.arr-qbittorrent-sync = {
    description = "Synchronize qBittorrent credentials in Arr applications";
    wants = [
      "qbittorrent.service"
      "sonarr.service"
      "radarr.service"
      "lidarr.service"
    ];
    after = [
      "qbittorrent.service"
      "sonarr.service"
      "radarr.service"
      "lidarr.service"
    ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "arr-qbittorrent-sync";
      RuntimeDirectoryMode = "0700";
      TimeoutStartSec = 240;
      Restart = "on-failure";
      RestartSec = 30;
      ExecStart = pkgs.writeShellScript "arr-qbittorrent-sync" ''
        status=0
        ${pkgs.coreutils}/bin/rm -f "$RUNTIME_DIRECTORY/restart-required"
        ${pkgs.python3}/bin/python ${../arr-qbittorrent-sync.py} \
          --password-file /srv/secrets/qbittorrent-webui-password \
          --restart-marker "$RUNTIME_DIRECTORY/restart-required" || status=$?

        if [[ -e "$RUNTIME_DIRECTORY/restart-required" ]]; then
          ${pkgs.systemd}/bin/systemctl restart qbittorrent.service || status=$?
        fi

        ${pkgs.python3}/bin/python ${../arr-qbittorrent-sync.py} \
          --password-file /srv/secrets/qbittorrent-webui-password \
          --sync-categories \
          --timeout 60 || status=$?
        exit "$status"
      '';

      # The Arr config directories are mode 0700 and owned by their
      # respective service users. This helper only needs to read their API
      # keys; retain the read/search DAC capability without granting write
      # access to otherwise private application state.
      CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" ];
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
    };
  };

  # Nixarr normally maps qBittorrent's internal API only when its optional qui
  # frontend is enabled. The native Web UI needs an explicit namespace mapping.
  vpnNamespaces.wg.portMappings = [
    {
      from = 8082;
      to = 8082;
    }
  ];

  # Nixarr also adds a 10.0.0.0/8 route through the bridge so services in the
  # namespace can reach private host networks. Proton's DNS (10.2.0.1) is in
  # that range, so without this more-specific route DNS queries never reach
  # the VPN gateway and every tracker appears to be unavailable.
  systemd.services.wg.serviceConfig.ExecStartPost = pkgs.writeShellScript "wg-route-proton-dns" ''
    set -euo pipefail
    ${pkgs.gawk}/bin/awk -F= '
      /^[[:space:]]*DNS[[:space:]]*=/ {
        value = $2
        gsub(/[[:space:]]/, "", value)
        count = split(value, dns, ",")
        for (i = 1; i <= count; i++) print dns[i]
      }
    ' /srv/secrets/protonvpn.conf |
      while read -r dns; do
        case "$dns" in
          *:*) ${pkgs.iproute2}/bin/ip -6 -n wg route replace "$dns/128" dev wg0 ;;
          *) ${pkgs.iproute2}/bin/ip -n wg route replace "$dns/32" dev wg0 ;;
        esac
      done
  '';

  # VPN-Confinement gives qBittorrent a fail-closed WireGuard namespace.
  # Preserve the existing localhost/LAN endpoint used by the Arr applications.
  systemd.services.qbt-webui-proxy = {
    description = "Host proxy for Nixarr qBittorrent Web UI";
    requires = [ "qbittorrent.service" ];
    after = [ "qbittorrent.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Restart = "on-failure";
      SuccessExitStatus = 143;
      ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:8082,bind=0.0.0.0,reuseaddr,fork TCP:192.168.15.1:8082";
    };
  };
}
