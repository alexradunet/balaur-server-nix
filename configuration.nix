{
  herdrPackage,
  piPackage,
  pkgs,
  ...
}:

let
  piSubagentsPackage = pkgs.callPackage ./pi-subagents.nix { };
  piWebAccessPackage = pkgs.callPackage ./pi-web-access.nix { };

  fastFlowLMPackage = pkgs.callPackage ./fastflowlm.nix { };
in
{
  # ------------------------------------------------------------
  # Nix
  # ------------------------------------------------------------

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "fastflowlm"
      "obsidian"
    ];

  # ------------------------------------------------------------
  # Boot
  # ------------------------------------------------------------

  boot.loader.systemd-boot.enable = false;

  boot.loader.efi.canTouchEfiVariables = true;

  boot.swraid.mdadmConf = ''
    MAILADDR root
  '';

  boot.loader.grub = {
    enable = true;
    efiSupport = true;

    # Keep a complete bootloader on both NVMe EFI partitions.
    mirroredBoots = [
      {
        path = "/boot";
        devices = [ "nodev" ];
      }
      {
        path = "/boot-fallback";
        devices = [ "nodev" ];
      }
    ];
  };

  # ------------------------------------------------------------
  # Networking
  # ------------------------------------------------------------

  networking.hostName = "balaur";

  # Gives us nmcli + nmtui, including an easy Wi-Fi wizard.
  networking.networkmanager.enable = true;

  # ------------------------------------------------------------
  # Locale
  # ------------------------------------------------------------

  time.timeZone = "Europe/Bucharest";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  # ------------------------------------------------------------
  # Principal desktop
  # ------------------------------------------------------------

  services.xserver.enable = true;
  services.xserver.autorun = true;
  services.xserver.displayManager.lightdm.enable = true;
  services.displayManager.defaultSession = "xfce";

  services.xserver.desktopManager.xfce = {
    enable = true;
    enableScreensaver = false;
  };
  services.pipewire.enable = false;
  services.speechd.enable = false;

  # ------------------------------------------------------------
  # User
  # ------------------------------------------------------------

  users.users.alex = {
    isNormalUser = true;
    description = "Alex";
    extraGroups = [
      "wheel"
      "networkmanager"
      "media"
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJyNg0fSXVLH2obdAQ9lX2LP4NjATTydZxvu6RguwRWx alex@yoga-laptop"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJb2YvlmOvpu8On8kAdU0bgNQXLSekrVu/s/L7W+XPGV alex@balaur.space"
    ];
  };

  security.sudo.extraRules = [
    {
      users = [ "alex" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # ------------------------------------------------------------
  # SSH
  # ------------------------------------------------------------

  services.openssh = {
    enable = true;

    settings = {
      AllowUsers = [ "alex" ];
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      X11Forwarding = false;
    };
  };

  # ------------------------------------------------------------
  # Services
  # ------------------------------------------------------------

  services.syncthing = {
    enable = true;
    user = "alex";
    group = "users";
    dataDir = "/home/alex";
    configDir = "/home/alex/.config/syncthing";
    guiAddress = "0.0.0.0:8383";
    openDefaultPorts = false;

    # Keep peers and folder sharing editable in the UI while ensuring the
    # mirrored personal partition is always present as a two-way sync folder.
    overrideDevices = false;
    overrideFolders = false;
    settings.folders.personal = {
      path = "/srv/personal";
      label = "Personal";
      type = "sendreceive";
      # ext4 creates this root-owned directory; it is filesystem metadata, not
      # personal data, and Syncthing cannot traverse it as the alex user.
      ignorePatterns = [ "/lost+found" ];
    };
  };

  # Never let Syncthing scan the empty mount point if the nofail disk is absent;
  # that could otherwise propagate deletions to peers.
  systemd.services.syncthing.unitConfig.RequiresMountsFor = [ "/srv/personal" ];

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
      whisparr = null;
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
    whisparr.enable = true;

    qbittorrent = {
      enable = true;
      vpn.enable = true;
      # Keep the native Web UI/API so the existing Arr download-client
      # configuration remains valid through the host-side proxy below.
      qui.enable = false;
      webuiPort = 8082;
      peerPort = 6881;

      # Whisparr does not yet accept qBittorrent 5.2's HTTP 204 authentication
      # response. Keep 5.1 until that client is updated.
      package = pkgs.qbittorrent-nox.overrideAttrs (_old: {
        version = "5.1.4";
        src = pkgs.fetchFromGitHub {
          owner = "qbittorrent";
          repo = "qBittorrent";
          tag = "release-5.1.4";
          hash = "sha256-9RfKir/e+8Kvln20F+paXqtWzC3KVef2kNGyk1YpSv4=";
        };
      });

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
  services.whisparr.settings.auth.required = "DisabledForLocalAddresses";

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

  services.home-assistant = {
    enable = true;
    openFirewall = false;
    extraComponents = [
      "default_config"
      "esphome"
      "google_translate"
      "hue"
      "ibeacon"
      "ipp"
      "met"
      "netatmo"
      "playstation_network"
      "radio_browser"
      "roborock"
      "samsungtv"
      "wiz"
    ];
    config = {
      default_config = { };
      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
      };
    };
  };

  # Mirrored application state for services such as Jellyfin and Immich.
  fileSystems."/srv/app-data" = {
    device = "/dev/disk/by-label/BALAUR_APP_DATA";
    fsType = "ext4";
    options = [
      "nofail"
      "nodev"
      "nosuid"
      "x-systemd.device-timeout=30s"
    ];
  };

  # Mirrored personal data, including the local photo archive.
  fileSystems."/srv/personal" = {
    device = "/dev/disk/by-label/BALAUR_PERSONAL";
    fsType = "ext4";
    options = [
      "nofail"
      "nodev"
      "nosuid"
      "noexec"
      "x-systemd.device-timeout=30s"
    ];
  };

  # Independent, non-redundant storage for replaceable downloaded media.
  fileSystems."/srv/media/ssd0" = {
    device = "/dev/disk/by-label/BALAUR_MEDIA_0";
    fsType = "ext4";
    options = [
      "nofail"
      "nodev"
      "nosuid"
      "noexec"
    ];
  };

  fileSystems."/srv/media/ssd1" = {
    device = "/dev/disk/by-label/BALAUR_MEDIA_1";
    fsType = "ext4";
    options = [
      "nofail"
      "nodev"
      "nosuid"
      "noexec"
    ];
  };

  # Keep the USB backup offline except while Borg is creating a daily snapshot.
  fileSystems."/mnt/balaur-backup" = {
    device = "/dev/disk/by-label/BALAUR_BACKUP";
    fsType = "ext4";
    options = [
      "noauto"
      "nofail"
      "nodev"
      "nosuid"
      "noexec"
      "x-systemd.device-timeout=10s"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /srv/secrets 0700 root root -"
    "d /srv/app-data 2775 root media -"
    "d /srv/app-data/seerr 0750 seerr seerr -"
    # Migrate files previously mapped through Prowlarr's DynamicUser namespace.
    "Z /srv/app-data/prowlarr - prowlarr prowlarr -"
    "d /srv/app-data/fastflowlm 0750 fastflowlm fastflowlm -"
    "d /srv/app-data/fastflowlm/models 0750 fastflowlm fastflowlm -"
    "d /srv/media/ssd0/downloads 2775 qbittorrent media -"
    "d /srv/media/ssd0/downloads/incomplete 2775 qbittorrent media -"
    "d /srv/media/ssd0/downloads/complete 2775 qbittorrent media -"
    "d /srv/media/ssd0/downloads/complete/radarr 2775 qbittorrent media -"
    "d /srv/media/ssd0/downloads/complete/whisparr 2775 qbittorrent media -"
    "d /srv/media/ssd0/library 2775 alex media -"
    "d /srv/media/ssd0/library/movies 2775 alex media -"
    "d /srv/media/ssd0/library/whisparr 2775 alex media -"
    "d /srv/media/ssd1/downloads 2775 qbittorrent media -"
    "d /srv/media/ssd1/downloads/incomplete 2775 qbittorrent media -"
    "d /srv/media/ssd1/downloads/complete 2775 qbittorrent media -"
    "d /srv/media/ssd1/downloads/complete/sonarr 2775 qbittorrent media -"
    "d /srv/media/ssd1/downloads/complete/lidarr 2775 qbittorrent media -"
    "d /srv/media/ssd1/library 2775 alex media -"
    "d /srv/media/ssd1/library/tv 2775 alex media -"
    "d /srv/media/ssd1/library/music 2775 alex media -"
    "d /srv/personal 2775 alex media -"
    "d /srv/media 2775 root media -"
    "d /srv/media/ssd0 2775 root media -"
    "d /srv/media/ssd1 2775 root media -"
    "d /mnt/balaur-backup 0700 root root -"
    "d /home/alex/.pi 0755 alex users -"
    "d /home/alex/.pi/agent 0755 alex users -"
    "d /home/alex/.pi/agent/extensions 0755 alex users -"
    "L+ /home/alex/.pi/agent/extensions/pi-subagents - - - - ${piSubagentsPackage}/lib/node_modules/@tintinweb/pi-subagents"
    "L+ /home/alex/.pi/agent/extensions/pi-web-access - - - - ${piWebAccessPackage}/lib/node_modules/pi-web-access"
  ];

  systemd.services.balaur-backup = {
    description = "Encrypted Borg backup to USB";
    unitConfig.ConditionPathExists = "/dev/disk/by-label/BALAUR_BACKUP";

    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "balaur-backup";
      StateDirectoryMode = "0700";
      LoadCredential = "passphrase:/var/lib/balaur-backup/passphrase";
      UMask = "0077";
      Nice = 10;
      IOSchedulingClass = "idle";
      ExecStart = pkgs.writeShellScript "balaur-backup" ''
        set -euo pipefail

        mountpoint=/mnt/balaur-backup
        repository="$mountpoint/borg"

        if ${pkgs.util-linux}/bin/mountpoint --quiet "$mountpoint"; then
          echo "$mountpoint is already mounted; refusing to manage another mount" >&2
          exit 1
        fi

        ${pkgs.util-linux}/bin/mount "$mountpoint"
        cleanup() {
          status=$?
          trap - EXIT
          ${pkgs.coreutils}/bin/sync
          if ! ${pkgs.util-linux}/bin/umount "$mountpoint"; then
            status=1
          fi
          exit "$status"
        }
        trap cleanup EXIT

        export BORG_BASE_DIR=/var/lib/balaur-backup
        export BORG_PASSCOMMAND="${pkgs.coreutils}/bin/cat $CREDENTIALS_DIRECTORY/passphrase"

        if [[ ! -d "$repository" ]]; then
          ${pkgs.borgbackup}/bin/borg init --encryption=repokey-blake2 "$repository"
        fi

        backup_status=0
        ${pkgs.borgbackup}/bin/borg create \
          --compression zstd,3 \
          --exclude-caches \
          --exclude /home/alex/.cache \
          --stats \
          "$repository::{hostname}-{now:%Y-%m-%dT%H:%M:%S}" \
          /home/alex || backup_status=$?

        # Borg uses status 1 for warnings such as a file changing during backup.
        if (( backup_status > 1 )); then
          exit "$backup_status"
        fi

        ${pkgs.borgbackup}/bin/borg prune \
          --glob-archives 'balaur-*' \
          --keep-daily 7 \
          --keep-weekly 4 \
          --keep-monthly 6 \
          --list \
          "$repository"

        ${pkgs.borgbackup}/bin/borg compact "$repository"
        exit "$backup_status"
      '';
    };
  };

  systemd.timers.balaur-backup = {
    description = "Daily encrypted Borg backup to USB";
    wantedBy = [ "timers.target" ];

    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };

  # FastFlowLM runs Qwen 3.6 MoE entirely on the Ryzen AI XDNA2 NPU. Linux 7.0+
  # selects the protocol-7 NPU firmware required by FastFlowLM, while the
  # portable release bundles the matching XRT userspace stack.
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelModules = [ "amdxdna" ];

  users.groups.fastflowlm = { };
  users.users.fastflowlm = {
    isSystemUser = true;
    group = "fastflowlm";
    extraGroups = [ "render" ];
  };

  systemd.services.fastflowlm = {
    description = "FastFlowLM Ryzen AI NPU model server";
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "srv-app\\x2ddata.mount"
    ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      FLM_DISABLE_UPDATE_CHECK = "1";
      FLM_MODEL_PATH = "/srv/app-data/fastflowlm/models";
      HOME = "/var/lib/fastflowlm";
    };

    serviceConfig = {
      User = "fastflowlm";
      Group = "fastflowlm";
      StateDirectory = "fastflowlm";
      WorkingDirectory = "/var/lib/fastflowlm";
      ExecStart = "${fastFlowLMPackage}/bin/flm serve qwen3.6-moe:35b-a3b --host 0.0.0.0 --port 8081 --ctx-len 32768 --cors 0";
      Restart = "on-failure";
      RestartSec = 10;
      LimitMEMLOCK = "infinity";

      DevicePolicy = "closed";
      DeviceAllow = [ "/dev/accel/accel0 rw" ];
      PrivateDevices = false;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ReadWritePaths = [ "/srv/app-data/fastflowlm/models" ];
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
    };
  };

  # Nixarr supplies a static Prowlarr account, but the upstream NixOS service
  # still enables DynamicUser. Disable it so systemd can reuse the existing
  # real /var/lib/prowlarr directory instead of requiring a private-state symlink.
  systemd.services.prowlarr.serviceConfig.DynamicUser = pkgs.lib.mkForce false;

  # Nixarr sets the shared-media umask for most services. Whisparr still needs
  # an explicit override in its current module.
  systemd.services.whisparr.serviceConfig.UMask = pkgs.lib.mkForce "0002";

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
  systemd.services.whisparr.unitConfig.RequiresMountsFor = pkgs.lib.mkAfter [
    "/srv/app-data"
    "/srv/media/ssd0"
  ];
  systemd.services.qbittorrent.unitConfig.RequiresMountsFor = pkgs.lib.mkAfter [
    "/srv/app-data"
    "/srv/media/ssd0"
    "/srv/media/ssd1"
  ];

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
      "whisparr.service"
    ];
    after = [
      "qbittorrent.service"
      "sonarr.service"
      "radarr.service"
      "lidarr.service"
      "whisparr.service"
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
        ${pkgs.python3}/bin/python ${./arr-qbittorrent-sync.py} \
          --password-file /srv/secrets/qbittorrent-webui-password \
          --restart-marker "$RUNTIME_DIRECTORY/restart-required" || status=$?

        if [[ -e "$RUNTIME_DIRECTORY/restart-required" ]]; then
          ${pkgs.systemd}/bin/systemctl restart qbittorrent.service || status=$?
        fi

        ${pkgs.python3}/bin/python ${./arr-qbittorrent-sync.py} \
          --password-file /srv/secrets/qbittorrent-webui-password \
          --sync-categories \
          --timeout 60 || status=$?
        exit "$status"
      '';

      CapabilityBoundingSet = "";
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

  # Xvnc provides a persistent virtual X display alongside the local XFCE session.
  systemd.services.web-desktop-vnc = {
    description = "Web desktop VNC server";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      DISPLAY = ":10";
      HOME = "/home/alex";
      XAUTHORITY = "/run/web-desktop/Xauthority";
      XDG_RUNTIME_DIR = "/run/web-desktop";
    };

    serviceConfig = {
      User = "alex";
      Group = "users";
      RuntimeDirectory = "web-desktop";
      RuntimeDirectoryMode = "0700";
      ExecStart = pkgs.writeShellScript "web-desktop-vnc" ''
        rm -f "$XAUTHORITY"
        cookie="$(${pkgs.util-linux}/bin/mcookie)"
        ${pkgs.xauth}/bin/xauth -f "$XAUTHORITY" add "$DISPLAY" . "$cookie"

        exec ${pkgs.tigervnc}/bin/Xvnc "$DISPLAY" \
          -geometry 1600x900 \
          -depth 24 \
          -interface 127.0.0.1 \
          -rfbport 5910 \
          -SecurityTypes None \
          -nolisten tcp
      '';
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.services.web-desktop-session = {
    description = "Web desktop XFCE session";
    requires = [ "web-desktop-vnc.service" ];
    after = [ "web-desktop-vnc.service" ];
    partOf = [ "web-desktop-vnc.service" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      DISPLAY = ":10";
      HOME = "/home/alex";
      XAUTHORITY = "/run/web-desktop/Xauthority";
      XDG_RUNTIME_DIR = "/run/web-desktop";
    };

    serviceConfig = {
      User = "alex";
      Group = "users";
      WorkingDirectory = "/home/alex";
      ExecStart = pkgs.writeShellScript "web-desktop-session" ''
        . /etc/profile

        for attempt in {1..100}; do
          if ${pkgs.xset}/bin/xset query >/dev/null 2>&1; then
            exec ${pkgs.dbus}/bin/dbus-run-session -- \
              ${pkgs.runtimeShell} ${pkgs.xfce4-session.xinitrc}
          fi
          sleep 0.1
        done

        echo "Xvnc did not become ready" >&2
        exit 1
      '';
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  systemd.services.web-desktop-novnc = {
    description = "Web desktop noVNC gateway";
    requires = [ "web-desktop-vnc.service" ];
    after = [ "web-desktop-vnc.service" ];
    partOf = [ "web-desktop-vnc.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.procps ];

    serviceConfig = {
      DynamicUser = true;
      ExecStart = "${pkgs.novnc}/bin/novnc --listen 0.0.0.0:6080 --vnc 127.0.0.1:5910 --file-only";
      Restart = "on-failure";
      RestartSec = 5;

      CapabilityBoundingSet = "";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
    };
  };

  # ttyd exposes Herdr's terminal UI without changing its persistent session model.
  systemd.services.herdr-web = {
    description = "Herdr web terminal";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HERDR_WEB_LISTEN = "0.0.0.0";
      HERDR_WEB_PORT = "7681";
      HOME = "/home/alex";
      SHELL = "${pkgs.bashInteractive}/bin/bash";
    };

    serviceConfig = {
      User = "alex";
      Group = "users";
      WorkingDirectory = "/home/alex";
      ExecStart = pkgs.writeShellScript "herdr-web" ''
        export PATH="/home/alex/.nix-profile/bin:/home/alex/.local/state/nix/profile/bin:/etc/profiles/per-user/alex/bin:/run/current-system/sw/bin:/run/wrappers/bin:$PATH"
        exec ${pkgs.ttyd}/bin/ttyd --interface "$HERDR_WEB_LISTEN" --port "$HERDR_WEB_PORT" --writable --check-origin ${herdrPackage}/bin/herdr
      '';
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # A dependency-free Node.js dashboard for host metrics and service links.
  systemd.services.balaur-dashboard = {
    description = "Balaur home dashboard";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      DASHBOARD_HOST = "0.0.0.0";
      DASHBOARD_PORT = "8080";
    };

    serviceConfig = {
      DynamicUser = true;
      ExecStart = "${pkgs.nodejs}/bin/node ${./dashboard}/server.mts";
      Restart = "on-failure";
      RestartSec = 5;

      CapabilityBoundingSet = "";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "strict";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
      UMask = "0077";
    };
  };

  # Expose application UIs and Syncthing transport only to networks that can
  # reach this host. The router must not forward these ports from the internet.
  networking.firewall.allowedTCPPorts = [
    22
    5055
    6080
    6969
    7681
    7878
    8080
    8081
    8082
    8096
    8123
    8383
    8686
    8989
    9696
    22000
  ];
  networking.firewall.allowedUDPPorts = [
    21027
    22000
  ];

  # ------------------------------------------------------------
  # Useful server tools
  # ------------------------------------------------------------

  environment.systemPackages = with pkgs; [
    vim
    git
    gh
    curl
    wget
    htop
    tmux
    chromium
    obsidian
    herdrPackage
    fastFlowLMPackage
    piPackage
    pciutils
    usbutils
    gptfdisk
    mdadm
    borgbackup
  ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  hardware.enableRedistributableFirmware = true;

  # DO NOT CHANGE after installation.
  system.stateVersion = "26.05";
}
