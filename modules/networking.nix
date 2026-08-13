{ ... }:

let
  lanTCPPorts = [
    22
    80
    8081
    8082
    8084
    8085
    8096
    8123
    9696
  ];
  lanUDPPorts = [ ];
in
{
  # These services are intended for the trusted home LAN and for WireGuard
  # clients routed by the router into the LAN. Keep the firewall
  # interface-scoped so a future VPN, bridge, or WAN interface does not
  # automatically inherit the application ports.
  networking.firewall.interfaces = {
    enp100s0 = {
      allowedTCPPorts = lanTCPPorts;
      allowedUDPPorts = lanUDPPorts;
    };
    wlp98s0 = {
      allowedTCPPorts = lanTCPPorts;
      allowedUDPPorts = lanUDPPorts;
    };
  };
}
