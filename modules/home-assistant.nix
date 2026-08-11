{ ... }:

{
  services.home-assistant = {
    enable = true;
    openFirewall = false;
    extraComponents = [
      "default_config"
      "esphome"
      "google_translate"
      "hue"
      "ibeacon"
      "ipp"
      "met"
      "netatmo"
      "playstation_network"
      "radio_browser"
      "roborock"
      "samsungtv"
      "wiz"
    ];
    config = {
      default_config = { };
      http = {
        server_host = "0.0.0.0";
        server_port = 8123;
      };
    };
  };
}
