{ config, lib, ... }:

{
  # Bluetooth and LAN discovery are part of the retained local-device
  # capability. Their discovery sockets are restricted to household-facing
  # interfaces; the Home Assistant HTTP port remains loopback-only.
  hardware.bluetooth.enable = true;

  networking.firewall.interfaces = lib.genAttrs config.balaur.network.trustedInterfaces (_: {
    allowedUDPPorts = lib.mkAfter [
      1900 # SSDP
      5353 # mDNS
    ];
  });

  services.home-assistant = {
    enable = true;
    configDir = "/srv/services/home-assistant";
    openFirewall = false;
    openFirewallForComponents = false;

    # Keep the integrations observed in the former household configuration
    # that correspond to local devices or their discovery. General content
    # integrations from that configuration are deliberately not retained.
    extraComponents = [
      "default_config"
      "esphome"
      "hue"
      "ibeacon"
      "ipp"
      "met"
      "netatmo"
      "playstation_network"
      "roborock"
      "samsungtv"
      "wiz"
    ];

    config = {
      default_config = { };
      http = {
        server_host = "127.0.0.1";
        server_port = 8123;
        use_x_forwarded_for = true;
        trusted_proxies = [ "127.0.0.1" ];
      };
    };
  };

  balaur.ingress.reverseProxies."home-assistant.home.arpa" = {
    backend = {
      host = "127.0.0.1";
      port = 8123;
    };
  };

  # The upstream module otherwise creates the home during activation, before a
  # failed data mount can be distinguished from an empty directory on md root.
  users.users = lib.mkIf config.services.home-assistant.enable {
    hass.createHome = lib.mkForce false;
  };

  systemd.services = {
    home-assistant-storage = {
      description = "Prepare mounted Home Assistant state";
      before = [ "home-assistant.service" ];
      requiredBy = [ "home-assistant.service" ];
      unitConfig = {
        RequiresMountsFor = [ "/srv/services" ];
        ConditionPathIsMountPoint = [ "/srv/services" ];
      };
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        install -d -m 0700 -o hass -g hass /srv/services/home-assistant
      '';
    };

    home-assistant = {
      requires = [ "home-assistant-storage.service" ];
      after = [ "home-assistant-storage.service" ];
      unitConfig = {
        RequiresMountsFor = [ "/srv/services" ];
        ConditionPathIsMountPoint = [ "/srv/services" ];
      };
    };
  };

  assertions = [
    {
      assertion = lib.hasPrefix "/srv/services/" config.services.home-assistant.configDir;
      message = "Home Assistant state must remain below protected /srv/services";
    }
  ];
}
