{ pkgs, ... }:

{
  # Preserve the UIDs/GIDs already assigned on this installed host. Nixarr's
  # fixed IDs are useful for fresh installs but would orphan existing state and
  # media files during an in-place migration.
  util-nixarr.globals = {
    uids = builtins.mapAttrs (_name: _uid: pkgs.lib.mkForce null) {
      jellyfin = null;
      qbittorrent = null;
    };
    gids.media = pkgs.lib.mkForce null;
  };

  # Nixarr remains a small, useful wrapper around Jellyfin, qBittorrent, shared
  # media permissions, and fail-closed WireGuard confinement. FlexGet is a
  # native NixOS service in flexget.nix; no Arr application is enabled.
  nixarr = {
    enable = true;
    mediaDir = "/srv/media/ssd0";
    stateDir = "/srv/app-data";

    vpn = {
      enable = true;
      wgConf = "/srv/secrets/protonvpn.conf";
    };

    jellyfin.enable = true;

    qbittorrent = {
      enable = true;
      vpn.enable = true;
      qui.enable = false;
      webuiPort = 8082;
      peerPort = 6881;

      extraConfig = {
        BitTorrent = {
          "Session\\DefaultSavePath" = "/srv/media/ssd0/downloads/complete";
          "Session\\TempPath" = "/srv/media/ssd0/downloads/incomplete";
        };
        Preferences = {
          "Downloads\\SavePath" = "/srv/media/ssd0/downloads/complete";
          "Downloads\\TempPath" = "/srv/media/ssd0/downloads/incomplete";
          # Every LAN request arrives through the namespace bridge/proxy, so
          # subnet bypass would effectively disable Web UI authentication.
          "WebUI\\AuthSubnetWhitelistEnabled" = false;
          "WebUI\\CSRFProtection" = true;
          "WebUI\\LocalHostAuth" = true;
        };
      };
    };
  };

  # Preserve the existing Jellyfin database during the in-place migration.
  services.jellyfin.dataDir = pkgs.lib.mkForce "/srv/app-data/jellyfin";

  # The storage filesystems are intentionally nofail so the host can still boot
  # degraded. Stop only the affected services instead of using empty mount
  # points on the OS filesystem.
  systemd.services.jellyfin.unitConfig.RequiresMountsFor = pkgs.lib.mkAfter [
    "/srv/app-data"
    "/srv/media/ssd0"
    "/srv/media/ssd1"
  ];
  systemd.services.qbittorrent.unitConfig.RequiresMountsFor = pkgs.lib.mkAfter [
    "/srv/app-data"
    "/srv/media/ssd0"
    "/srv/media/ssd1"
  ];

  systemd.services.qbittorrent.serviceConfig.UMask = pkgs.lib.mkForce "0002";

  # NixOS regenerates qBittorrent.conf on every service start. Inject a stable,
  # host-local Web UI password afterward so FlexGet and browser sessions retain
  # one credential without putting it in the Nix store.
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
  # the VPN gateway and every tracker appears unavailable.
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

  # VPN-Confinement gives qBittorrent a fail-closed WireGuard namespace while
  # this small proxy provides the authenticated host/LAN API endpoint.
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
