{ ... }:

{
  # The baseline is administrative only. Later tickets may add narrowly scoped
  # service ports after their listeners and access controls exist.
  networking.firewall = {
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
    interfaces = {
      enp100s0 = {
        allowedTCPPorts = [ 22 ];
        allowedUDPPorts = [ ];
      };
      wlp98s0 = {
        allowedTCPPorts = [ 22 ];
        allowedUDPPorts = [ ];
      };
    };
  };
}
