{ herdrPackage, pkgs, ... }:

let
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
        override_local_dns = true;
        nameservers.global = [
          "1.1.1.1"
          "1.0.0.1"
        ];
        extra_records = map (name: {
          inherit name;
          type = "A";
          value = "100.64.0.1";
        }) [
          "dashboard.balaur.space"
          "desktop.balaur.space"
          "herdr.balaur.space"
          "llama.balaur.space"
          "syncthing.balaur.space"
        ];
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

    # Keep the short MagicDNS name convenient while using the dashboard's full name.
    virtualHosts."balaur" = {
      default = true;

      locations."/".return = "302 https://dashboard.balaur.space$request_uri";
    };

    # ACME validates these names publicly, but Headscale resolves them to the tailnet address.
    virtualHosts."dashboard.balaur.space" = {
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

    # Preserve the previous dashboard URL for existing bookmarks.
    virtualHosts."balaur.tailnet.balaur.space" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        return = "302 https://dashboard.balaur.space$request_uri";
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

    virtualHosts."syncthing.balaur.space" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:8383";
        proxyWebsockets = true;
        recommendedProxySettings = false;
        extraConfig = ''
          proxy_set_header Host 127.0.0.1:8383;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
          proxy_set_header X-Forwarded-Host $host;
          proxy_set_header X-Forwarded-Server $hostname;
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
        '';
      };
    };

    virtualHosts."herdr.balaur.space" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:7681";
        proxyWebsockets = true;
        extraConfig = ''
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
        '';
      };
    };

    virtualHosts."llama.balaur.space" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:8081";
        proxyWebsockets = true;
        extraConfig = ''
          allow 100.64.0.0/10;
          allow fd7a:115c:a1e0::/48;
          deny all;
        '';
      };
    };

    virtualHosts."desktop.balaur.space" = {
      enableACME = true;
      forceSSL = true;

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

  services.llama-cpp = {
    enable = true;
    host = "127.0.0.1";
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
    ];
  };

  systemd.services.llama-cpp.serviceConfig.ProcSubset = pkgs.lib.mkForce "all";
  systemd.services.llama-cpp.environment.XDG_CACHE_HOME = "/var/cache/llama-cpp";

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
    path = [ pkgs.procps ];

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

  # ttyd exposes Herdr's terminal UI without changing its persistent session model.
  systemd.services.herdr-web = {
    description = "Herdr web terminal";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    environment = {
      HERDR_WEB_LISTEN = "127.0.0.1";
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
    obsidian
    herdrPackage
    llamaCppPackage
    opencode
    pciutils
    usbutils
    mdadm
  ];

  hardware.enableRedistributableFirmware = true;

  # DO NOT CHANGE after installation.
  system.stateVersion = "26.05";
}
