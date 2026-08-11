{ ... }:

{
  services.memos = {
    enable = true;
    dataDir = "/srv/app-data/memos";
    openFirewall = false;
    settings = {
      MEMOS_MODE = "prod";
      MEMOS_ADDR = "0.0.0.0";
      MEMOS_PORT = "5230";
      MEMOS_DATA = "/srv/app-data/memos";
      MEMOS_DRIVER = "sqlite";
      MEMOS_INSTANCE_URL = "http://balaur.home.arpa:5230";
    };
  };

  # Keep the service stopped rather than writing into the empty nofail mount
  # point when the application-data disk is unavailable.
  systemd.services.memos.unitConfig.RequiresMountsFor = [ "/srv/app-data" ];
}
