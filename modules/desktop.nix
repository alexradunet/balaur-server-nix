{ ... }:

{
  # ------------------------------------------------------------
  # Principal desktop
  # ------------------------------------------------------------

  services.xserver.enable = true;
  services.xserver.autorun = true;
  services.xserver.displayManager.lightdm.enable = true;
  services.displayManager.defaultSession = "xfce";

  services.xserver.desktopManager.xfce = {
    enable = true;
    enableScreensaver = false;
  };
  services.pipewire.enable = false;
  services.speechd.enable = false;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  hardware.enableRedistributableFirmware = true;
}
