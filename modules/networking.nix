{ ... }:

{
  # Expose application UIs and Syncthing transport only to networks that can
  # reach this host. The router must not forward these ports from the internet.
  networking.firewall.allowedTCPPorts = [
    22
    5055
    6080
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
    8989
    9696
    22000
  ];
  networking.firewall.allowedUDPPorts = [
    21027
    22000
  ];
}
