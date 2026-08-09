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
    guiAddress = "0.0.0.0:8384";
    openDefaultPorts = true;
  };

  # Paseo runs agents with Alex's development environment and uses our relay.
  services.paseo = {
    enable = true;
    user = "alex";
    group = "users";
    dataDir = "/home/alex/.paseo";
    listenAddress = "0.0.0.0";
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

    environment.PASEO_RELAY_ENABLED = "true";
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
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      SystemCallArchitectures = "native";
      UMask = "0077";
    };
  };

  # OpenCode is reachable only from authenticated devices on the tailnet.
  systemd.services.opencode-web = {
    description = "OpenCode web interface";
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    environment.HOME = "/home/alex";

    serviceConfig = {
      User = "alex";
      Group = "users";
      WorkingDirectory = "/home/alex";
      ExecStart = "${pkgs.opencode}/bin/opencode web --hostname 0.0.0.0 --port 4096";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [
    4096
    6767
    8080
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
