{ config, pkgs }:

let
  inherit (pkgs) lib;
  trustedInterfaces = [
    "enp100s0"
    "wlp98s0"
  ];
  assertions = [
    {
      assertion =
        config.services.openssh.enable
        && !config.services.openssh.openFirewall
        && config.services.openssh.settings.AllowUsers == [ "alex" ]
        && !config.services.openssh.settings.KbdInteractiveAuthentication
        && config.services.openssh.settings.PermitRootLogin == "no"
        && !config.services.openssh.settings.PasswordAuthentication
        && !config.services.openssh.settings.X11Forwarding;
      message = "SSH must remain key-only, root-disabled, and restricted to Alex";
    }
    {
      assertion =
        config.networking.firewall.allowedTCPPorts == [ ]
        && config.networking.firewall.allowedUDPPorts == [ ]
        && lib.all (
          interface:
          config.networking.firewall.interfaces.${interface}.allowedTCPPorts == [ 22 ]
          && config.networking.firewall.interfaces.${interface}.allowedUDPPorts == [ ]
        ) trustedInterfaces;
      message = "the baseline firewall must expose only SSH on trusted LAN interfaces";
    }
    {
      assertion =
        lib.all
          (
            port:
            !builtins.elem port config.networking.firewall.allowedTCPPorts
            && !builtins.elem port config.networking.firewall.allowedUDPPorts
            && lib.all (
              interface:
              !builtins.elem port config.networking.firewall.interfaces.${interface}.allowedTCPPorts
              && !builtins.elem port config.networking.firewall.interfaces.${interface}.allowedUDPPorts
            ) trustedInterfaces
          )
          [
            53
            80
            443
            6881
            8080
            8081
            8082
            8084
            8085
            8096
            8123
            9696
            11000
          ];
      message = "DNS, proxy, dashboard, and raw application ports must remain closed";
    }
  ];
  failures = map (entry: entry.message) (builtins.filter (entry: !entry.assertion) assertions);
in
if failures != [ ] then
  throw "Balaur access/networking invariant failures:\n${
    lib.concatMapStringsSep "\n" (failure: "- ${failure}") failures
  }"
else
  pkgs.runCommand "balaur-access-networking-tests" { } ''
    mkdir -p "$out"
    printf '%s\n' 'Access and networking baseline invariants passed.' > "$out/result"
  ''
