{ lib, pkgs, ... }:

{
  services.trilium-server = {
    enable = true;
    package = pkgs.trilium-next-server;
    dataDir = "/srv/app-data/trilium";
    instanceName = "Trilium";
    noBackup = false;
    noAuthentication = false;
    host = "127.0.0.1";
    port = 11000;
  };

  # Caddy publishes the authenticated application on the trusted LAN while the
  # Trilium process remains host-local.
  services.caddy.virtualHosts."http://balaur.home.arpa:8084".extraConfig = ''
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
