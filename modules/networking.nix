{ ... }:

let
  lanTCPPorts = [
    22
    80
    5230
    7878
    8081
    8082
    8083
    8096
    8123
    8383
    8989
    9696
    22000
  ];
  lanUDPPorts = [
    21027
    22000
  ];
in
{
  # These services are intended for the trusted home LAN only. Keep the
  # firewall interface-scoped so a future VPN, bridge, or WAN interface does
  # not automatically inherit the application ports.
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
