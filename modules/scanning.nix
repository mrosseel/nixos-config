{ pkgs, ... }:
{
  hardware.sane = {
    enable = true;
    drivers.scanSnap.enable = true;
  };

  environment.systemPackages = with pkgs; [
    simple-scan
  ];
}
