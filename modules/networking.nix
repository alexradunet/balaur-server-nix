{ ... }:

{
  # Expose application UIs and Syncthing transport only to networks that can
  # reach this host. The router must not forward these ports from the internet.
  networking.firewall.allowedTCPPorts = [
    22
    80
    6080
    7681
    7878
    8081
    8082
    8096
    8123
    8383
    8989
    22000
  ];
  networking.firewall.allowedUDPPorts = [
    21027
    22000
  ];
}
