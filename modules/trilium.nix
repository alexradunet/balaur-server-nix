{ lib, pkgs, ... }:

{
  services.trilium-server = {
    enable = true;
    # Keep TriliumNext current while nixpkgs catches up with upstream releases.
    package = pkgs.trilium-next-server.overrideAttrs (old: rec {
      version = "0.104.1";
      src = pkgs.fetchurl {
        url =
          if pkgs.stdenv.hostPlatform.isx86_64 then
            "https://github.com/TriliumNext/Trilium/releases/download/v${version}/TriliumNotes-Server-v${version}-linux-x64.tar.xz"
          else if pkgs.stdenv.hostPlatform.isAarch64 then
            "https://github.com/TriliumNext/Trilium/releases/download/v${version}/TriliumNotes-Server-v${version}-linux-arm64.tar.xz"
          else
            throw "TriliumNext server is not supported on this platform";
        hash =
          if pkgs.stdenv.hostPlatform.isx86_64 then
            "sha256-Ym8gcD0Rsp7rw5S5CHHW/Sh69JiyEOo3+U22nEs6yHg="
          else if pkgs.stdenv.hostPlatform.isAarch64 then
            "sha256-yIcM9BzrNT5gLbb+DaiJINQyIuygdmDJloHQ424OTxI="
          else
            throw "TriliumNext server is not supported on this platform";
      };
    });
    dataDir = "/srv/app-data/trilium";
    instanceName = "Trilium";
    noBackup = false;
    noAuthentication = false;
    host = "127.0.0.1";
    port = 11000;
  };

  # Caddy is the only network-facing listener. Trilium's sync protocol uses
  # WebSockets; Caddy's reverse_proxy handles the upgrade automatically.
  systemd.services.trilium-server.environment.TRILIUM_NETWORK_TRUSTEDREVERSEPROXY = "127.0.0.1";

  services.caddy.virtualHosts."https://192.168.50.2:8084".extraConfig = ''
    tls internal
    reverse_proxy 127.0.0.1:11000
  '';

  # Pocket Trilium cannot use the private Caddy CA. This plain-HTTP endpoint
  # is reachable only from the trusted LAN/WireGuard interfaces; never forward
  # port 8085 from the router's WAN.
  services.caddy.virtualHosts."http://192.168.50.2:8085".extraConfig = ''
    reverse_proxy 127.0.0.1:11000
  '';

  # Never let Trilium initialize a database on the OS disk when the nofail
  # application-data filesystem is absent.
  systemd.services.trilium-server.unitConfig.RequiresMountsFor = [ "/srv/app-data" ];

  systemd.services.trilium-server.serviceConfig = {
    CapabilityBoundingSet = "";
    LockPersonality = true;
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = lib.mkForce true;
    ProtectClock = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectHostname = true;
    ProtectKernelLogs = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    ReadWritePaths = [ "/srv/app-data/trilium" ];
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
}
