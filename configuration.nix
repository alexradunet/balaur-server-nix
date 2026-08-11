{
  herdrPackage,
  piPackage,
  pkgs,
  ...
}:

let
  piSubagentsPackage = pkgs.callPackage ./pi-subagents.nix { };
  piWebAccessPackage = pkgs.callPackage ./pi-web-access.nix { };

  llamaCppPackage =
    (pkgs.llama-cpp.override {
      rocmSupport = true;
      rocmGpuTargets = [ "gfx1150" ];
    }).overrideAttrs
      {
        version = "10336";
        src = pkgs.fetchzip {
          url = "https://github.com/ggml-org/llama.cpp/archive/refs/tags/b10336.tar.gz";
          hash = "sha256-Yyc+LbZ6BMBww0Wno9DlM3il+ol+ahh3S/r8NbDH/ss=";
          postFetch = ''
            echo f401bb1 > "$out/COMMIT"
          '';
        };
        npmDepsHash = "sha256-FHvd2bMvBc9EXrJEzu8EN78oUVSLcOKYCc0232V+L4A=";
      };
in
{
  # ------------------------------------------------------------
  # Nix
  # ------------------------------------------------------------

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nixpkgs.config.allowUnfreePredicate = pkg: pkgs.lib.getName pkg == "obsidian";

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
  };

  services.jellyfin = {
    enable = true;
    openFirewall = false;
    dataDir = "/srv/app-data/jellyfin";
    configDir = "/srv/app-data/jellyfin/config";
    logDir = "/srv/app-data/jellyfin/log";
  };

  services.prowlarr = {
    enable = true;
    openFirewall = false;
    dataDir = "/srv/app-data/prowlarr";
  };

  services.sonarr = {
    enable = true;
    openFirewall = false;
    dataDir = "/srv/app-data/sonarr";
  };

  services.radarr = {
    enable = true;
    openFirewall = false;
    dataDir = "/srv/app-data/radarr";
  };

  services.lidarr = {
    enable = true;
    openFirewall = false;
    dataDir = "/srv/app-data/lidarr";
  };

  services.readarr = {
    enable = true;
    openFirewall = false;
    dataDir = "/srv/app-data/readarr";
  };

  services.whisparr = {
    enable = true;
    openFirewall = false;
    dataDir = "/srv/app-data/whisparr";
  };

  services.bazarr = {
    enable = true;
    openFirewall = false;
    dataDir = "/srv/app-data/bazarr";
  };

  services.qbittorrent = {
    enable = true;
    # Readarr and Whisparr do not yet accept qBittorrent 5.2's HTTP 204
    # authentication response. Keep 5.1 until those clients are updated.
    package = pkgs.qbittorrent-nox.overrideAttrs (_old: {
      version = "5.1.4";
      src = pkgs.fetchFromGitHub {
        owner = "qbittorrent";
        repo = "qBittorrent";
        tag = "release-5.1.4";
        hash = "sha256-9RfKir/e+8Kvln20F+paXqtWzC3KVef2kNGyk1YpSv4=";
      };
    });
    openFirewall = false;
    profileDir = "/srv/app-data/qbittorrent";
    webuiPort = 8082;
    torrentingPort = 6881;
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

  users.groups.media = { };
  users.groups.prowlarr = { };
  users.users.prowlarr = {
    isSystemUser = true;
    group = "prowlarr";
  };
  users.users.jellyfin.extraGroups = [ "media" ];
  users.users.sonarr.extraGroups = [ "media" ];
  users.users.radarr.extraGroups = [ "media" ];
  users.users.lidarr.extraGroups = [ "media" ];
  users.users.readarr.extraGroups = [ "media" ];
  users.users.whisparr.extraGroups = [ "media" ];
  users.users.bazarr.extraGroups = [ "media" ];
  users.users.qbittorrent.extraGroups = [ "media" ];

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
    "d /srv/app-data 2775 root media -"
    "d /srv/app-data/jellyfin 0750 jellyfin jellyfin -"
    "d /srv/app-data/sonarr 0750 sonarr sonarr -"
    "d /srv/app-data/radarr 0750 radarr radarr -"
    "d /srv/app-data/lidarr 0750 lidarr lidarr -"
    "d /srv/app-data/readarr 0750 readarr readarr -"
    "d /srv/app-data/whisparr 0750 whisparr whisparr -"
    "d /srv/app-data/bazarr 0750 bazarr bazarr -"
    "d /srv/app-data/qbittorrent 0750 qbittorrent qbittorrent -"
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
    "d /srv/media/ssd1/downloads/complete/readarr 2775 qbittorrent media -"
    "d /srv/media/ssd1/library 2775 alex media -"
    "d /srv/media/ssd1/library/tv 2775 alex media -"
    "d /srv/media/ssd1/library/music 2775 alex media -"
    "d /srv/media/ssd1/library/books 2775 alex media -"
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

  services.llama-cpp = {
    enable = true;
    host = "0.0.0.0";
    port = 8081;
    package = llamaCppPackage;
    extraFlags = [
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
      "--sleep-idle-seconds"
      "300"
    ];
  };

  # Prowlarr's upstream module uses a dynamic user with a custom bind-mounted
  # data directory. A static service account prevents tmpfiles from revoking
  # database access during later system activations.
  systemd.services.prowlarr.serviceConfig = {
    DynamicUser = pkgs.lib.mkForce false;
    User = "prowlarr";
    Group = "prowlarr";
  };
  systemd.tmpfiles.settings."10-prowlarr"."/srv/app-data/prowlarr".d = {
    user = pkgs.lib.mkForce "prowlarr";
    group = pkgs.lib.mkForce "prowlarr";
    mode = pkgs.lib.mkForce "0750";
  };

  # Keep downloaded and imported files writable by every media service.
  systemd.services.sonarr.serviceConfig.UMask = pkgs.lib.mkForce "0002";
  systemd.services.radarr.serviceConfig.UMask = pkgs.lib.mkForce "0002";
  systemd.services.lidarr.serviceConfig.UMask = pkgs.lib.mkForce "0002";
  systemd.services.readarr.serviceConfig.UMask = pkgs.lib.mkForce "0002";
  systemd.services.whisparr.serviceConfig.UMask = pkgs.lib.mkForce "0002";
  systemd.services.bazarr.serviceConfig.UMask = pkgs.lib.mkForce "0002";
  # Isolate qBittorrent in a fail-closed Proton WireGuard namespace. The host
  # proxy preserves both localhost Arr access and the LAN Web UI.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  networking.firewall.trustedInterfaces = [ "qbt-host" ];
  networking.nat = {
    enable = true;
    internalInterfaces = [ "qbt-host" ];
  };

  systemd.services.qbt-vpn-netns = {
    description = "qBittorrent VPN network namespace";
    before = [ "qbt-vpn.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [
      pkgs.iproute2
      pkgs.nftables
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "qbt-vpn-netns-up" ''
        set -eu
        ip netns add qbt-vpn
        ip link add qbt-host type veth peer name qbt-ns
        ip link set qbt-ns netns qbt-vpn
        ip address add 10.200.0.1/30 dev qbt-host
        ip link set qbt-host up
        ip netns exec qbt-vpn ip link set lo up
        ip netns exec qbt-vpn ip address add 10.200.0.2/30 dev qbt-ns
        ip netns exec qbt-vpn ip link set qbt-ns up
        ip netns exec qbt-vpn ip route add default via 10.200.0.1
        ip netns exec qbt-vpn nft -f - <<'EOF'
        table inet qbt_killswitch {
          chain input {
            type filter hook input priority filter; policy drop;
            iifname "lo" accept
            ct state established,related accept
            iifname "qbt-ns" ip saddr 10.200.0.1 tcp dport 8082 accept
          }
          chain output {
            type filter hook output priority filter; policy drop;
            oifname "lo" accept
            ct state established,related accept
            oifname "wg0" accept
            oifname "qbt-ns" ip daddr 185.163.110.98 udp dport 51820 accept
            oifname "qbt-ns" ip daddr 10.200.0.1 tcp sport 8082 accept
          }
        }
        EOF
      '';
      ExecStop = pkgs.writeShellScript "qbt-vpn-netns-down" ''
        ip link delete qbt-host 2>/dev/null || true
        ip netns delete qbt-vpn 2>/dev/null || true
      '';
    };
  };

  systemd.services.qbt-vpn = {
    description = "Proton WireGuard for qBittorrent";
    requires = [ "qbt-vpn-netns.service" ];
    after = [
      "qbt-vpn-netns.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    before = [ "qbittorrent.service" ];
    path = [
      pkgs.gawk
      pkgs.gnugrep
      pkgs.iproute2
      pkgs.nftables
      pkgs.procps
      pkgs.wireguard-tools
    ];
    unitConfig.ConditionPathExists = "/srv/secrets/protonvpn.conf";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "qbt-vpn";
      RuntimeDirectoryMode = "0700";
      ExecStart = pkgs.writeShellScript "qbt-vpn-up" ''
        set -eu
        # wg-quick's DNS integration would alter host DNS. qBittorrent gets a
        # private resolv.conf instead and reaches Proton DNS through wg0.
        awk '!/^[[:space:]]*DNS[[:space:]]*=/' \
          /srv/secrets/protonvpn.conf > /run/qbt-vpn/wg0.conf
        chmod 600 /run/qbt-vpn/wg0.conf
        printf 'nameserver 10.2.0.1\n' > /run/qbt-vpn/resolv.conf
        ip netns exec qbt-vpn wg-quick up /run/qbt-vpn/wg0.conf
      '';
      ExecStop = pkgs.writeShellScript "qbt-vpn-down" ''
        ip netns exec qbt-vpn wg-quick down /run/qbt-vpn/wg0.conf || true
      '';
    };
  };

  systemd.services.qbittorrent = {
    requires = [ "qbt-vpn.service" ];
    after = [ "qbt-vpn.service" ];
    serviceConfig = {
      UMask = pkgs.lib.mkForce "0002";
      NetworkNamespacePath = "/run/netns/qbt-vpn";
      BindReadOnlyPaths = "/run/qbt-vpn/resolv.conf:/etc/resolv.conf";
    };
  };

  systemd.services.qbt-webui-proxy = {
    description = "Host proxy for qBittorrent VPN Web UI";
    requires = [ "qbittorrent.service" ];
    after = [ "qbittorrent.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Restart = "on-failure";
      SuccessExitStatus = 143;
      ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:8082,bind=0.0.0.0,reuseaddr,fork TCP:10.200.0.2:8082";
    };
  };

  systemd.services.llama-cpp.serviceConfig.ProcSubset = pkgs.lib.mkForce "all";
  systemd.services.llama-cpp.environment.XDG_CACHE_HOME = "/var/cache/llama-cpp";

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
    6080
    6767
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
    8787
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
    llamaCppPackage
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
