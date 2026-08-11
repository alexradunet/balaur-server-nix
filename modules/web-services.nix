{ herdrPackage, pkgs, ... }:

{
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
      # The desktop runs as alex and has no application authentication. Keep the
      # gateway loopback-only; use an SSH tunnel for remote access.
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
      # Herdr is an administrative shell as alex; expose it only through an SSH tunnel.
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

  # Keep the dashboard private; Caddy exposes it on the standard HTTP port.
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
      ExecStart = "${pkgs.nodejs}/bin/node ${../dashboard}/server.mts";
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

  # One simple entry point for the dashboard; keep the other application ports
  # unchanged until there is a concrete need for per-service hostnames.
  services.caddy = {
    enable = true;
    virtualHosts."http://balaur.home.arpa".extraConfig = ''
      reverse_proxy 127.0.0.1:8080
    '';
  };
}
