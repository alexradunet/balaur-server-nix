{ paseoRelayPackage, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # ------------------------------------------------------------
  # Nix
  # ------------------------------------------------------------

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
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
  # Optional local desktop
  # ------------------------------------------------------------

  # Log in on a TTY and run `sway`; no display manager starts at boot.
  programs.sway = {
    enable = true;
    xwayland.enable = false;
    extraPackages = with pkgs; [
      foot
      luakit
      wmenu
    ];
  };

  # XFCE runs only inside the persistent browser-accessible VNC session below.
  services.xserver.desktopManager.xfce = {
    enable = true;
    enableScreensaver = false;
  };

  services.xserver.autorun = false;
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
    ];
  };

  # Share sudo credentials across terminals and non-interactive processes.
  security.sudo.extraConfig = ''
    Defaults timestamp_type=global
  '';

  # ------------------------------------------------------------
  # SSH
  # ------------------------------------------------------------

  services.openssh = {
    enable = true;

    settings = {
      AllowUsers = [ "alex" ];
      PermitRootLogin = "no";
      PasswordAuthentication = true;
    };
  };

  # ------------------------------------------------------------
  # Headscale
  # ------------------------------------------------------------

  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = 8082;

    settings = {
      server_url = "https://headscale.balaur.space";

      dns = {
        magic_dns = true;
        base_domain = "tailnet.balaur.space";
        override_local_dns = false;
      };
    };
  };

  services.headplane = {
    enable = true;

    settings = {
      server = {
        base_url = "https://headscale.balaur.space";
        cookie_secret_path = "/var/lib/headplane/cookie-secret";
      };

      headscale = {
        url = "http://127.0.0.1:8082";
        public_url = "https://headscale.balaur.space";
      };

      # Headscale's declarative Nix configuration is intentionally read-only.
      integration.proc.enabled = false;
    };
  };

  # Keep the session secret out of the world-readable Nix store.
  systemd.services.headplane.preStart = ''
    if [[ ! -s /var/lib/headplane/cookie-secret ]]; then
      umask 077
      ${pkgs.openssl}/bin/openssl rand -hex 16 > /var/lib/headplane/cookie-secret
    fi
  '';

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Keep the short MagicDNS name convenient while using the certificate's full name.
    virtualHosts."balaur" = {
      default = true;

      locations."/".return = "302 https://balaur.tailnet.balaur.space$request_uri";
    };

    # ACME validates this name publicly, but Headscale resolves it to the tailnet address.
    virtualHosts."balaur.tailnet.balaur.space" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:8080";
        proxyWebsockets = true;
        extraConfig = ''
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
        '';
      };
    };

    virtualHosts."headscale.balaur.space" = {
      enableACME = true;
      forceSSL = true;

      locations."= /".return = "302 /admin/";

      locations."/admin/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
      };

      locations."/" = {
        proxyPass = "http://127.0.0.1:8082";
        proxyWebsockets = true;
      };
    };

    virtualHosts."relay.balaur.space" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:4000";
        proxyWebsockets = true;
      };
    };

    virtualHosts."syncthing-tailnet" = {
      serverName = "balaur.tailnet.balaur.space";
      onlySSL = true;
      useACMEHost = "balaur.tailnet.balaur.space";
      listen = [
        {
          addr = "0.0.0.0";
          port = 8384;
          ssl = true;
        }
        {
          addr = "[::0]";
          port = 8384;
          ssl = true;
        }
      ];

      locations."/" = {
        proxyPass = "http://127.0.0.1:8383";
        proxyWebsockets = true;
        extraConfig = ''
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
        '';
      };
    };

    virtualHosts."paseo-tailnet" = {
      serverName = "balaur.tailnet.balaur.space";
      onlySSL = true;
      useACMEHost = "balaur.tailnet.balaur.space";
      listen = [
        {
          addr = "0.0.0.0";
          port = 6767;
          ssl = true;
        }
        {
          addr = "[::0]";
          port = 6767;
          ssl = true;
        }
      ];

      locations."/" = {
        proxyPass = "http://127.0.0.1:6768";
        proxyWebsockets = true;
        extraConfig = ''
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
        '';
      };
    };

    # Tailnet web services terminate TLS in nginx and keep their backends on loopback.
    virtualHosts."zellij-tailnet" = {
      serverName = "balaur.tailnet.balaur.space";
      onlySSL = true;
      useACMEHost = "balaur.tailnet.balaur.space";
      listen = [
        {
          addr = "0.0.0.0";
          port = 8081;
          ssl = true;
        }
        {
          addr = "[::0]";
          port = 8081;
          ssl = true;
        }
      ];

      locations."/" = {
        proxyPass = "http://127.0.0.1:8083";
        proxyWebsockets = true;
        extraConfig = ''
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
        '';
      };
    };

    virtualHosts."desktop-tailnet" = {
      serverName = "balaur.tailnet.balaur.space";
      onlySSL = true;
      useACMEHost = "balaur.tailnet.balaur.space";
      listen = [
        {
          addr = "0.0.0.0";
          port = 8084;
          ssl = true;
        }
        {
          addr = "[::0]";
          port = 8084;
          ssl = true;
        }
      ];

      locations."= /".return = "302 /vnc.html?autoconnect=1&resize=remote";

      locations."/" = {
        proxyPass = "http://127.0.0.1:6080";
        proxyWebsockets = true;
        extraConfig = ''
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
        '';
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "hello@alexradu.net";
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
  };

  services.syncthing = {
    enable = true;
    user = "alex";
    group = "users";
    dataDir = "/home/alex";
    configDir = "/home/alex/.config/syncthing";
    guiAddress = "127.0.0.1:8383";
    openDefaultPorts = true;
  };

  # Paseo runs agents with Alex's development environment and uses our relay.
  services.paseo = {
    enable = true;
    user = "alex";
    group = "users";
    dataDir = "/home/alex/.paseo";
    listenAddress = "127.0.0.1";
    port = 6768;
    hostnames = [
      "balaur"
      "balaur.tailnet.balaur.space"
    ];

    relay = {
      enable = true;
      mode = "remote";
      host = "relay.balaur.space";
      port = 443;
      useTls = true;
    };

    environment = {
      PASEO_RELAY_ENABLED = "true";
      PASEO_WEB_UI_ENABLED = "true";
    };
  };

  # Keep Zellij on loopback and expose it through the tailnet-only nginx port.
  systemd.services.zellij-web = {
    description = "Zellij web terminal";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment.HOME = "/home/alex";

    serviceConfig = {
      User = "alex";
      Group = "users";
      WorkingDirectory = "/home/alex";
      ExecStart = "${pkgs.zellij}/bin/zellij web --ip 127.0.0.1 --port 8083";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Xvnc provides a persistent virtual X display without affecting local Sway.
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

    serviceConfig = {
      DynamicUser = true;
      ExecStart = "${pkgs.novnc}/bin/novnc --listen 127.0.0.1:6080 --vnc 127.0.0.1:5910 --file-only";
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
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
    };
  };

  systemd.services.paseo-relay = {
    description = "Paseo relay";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HOME = "/var/lib/paseo-relay";
      PASEO_RELAY_HOST = "127.0.0.1";
      PASEO_RELAY_PORT = "4000";
      PASEO_RELAY_MIN_CLUSTER_SIZE = "1";
    };

    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "paseo-relay";
      WorkingDirectory = "/var/lib/paseo-relay";
      ExecStart = "${paseoRelayPackage}/bin/paseo_relay start";
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
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
      UMask = "0077";
    };
  };

  # A dependency-free Node.js dashboard for host metrics and service links.
  systemd.services.balaur-dashboard = {
    description = "Balaur home dashboard";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      DASHBOARD_HOST = "127.0.0.1";
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
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
      UMask = "0077";
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    6767
    8081
    8084
    8384
  ];

  networking.firewall.allowedTCPPorts = [
    22
    80
    443
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
    zellij
    opencode
    pciutils
    usbutils
    mdadm
  ];

  hardware.enableRedistributableFirmware = true;

  # DO NOT CHANGE after installation.
  system.stateVersion = "26.05";
}
