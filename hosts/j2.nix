{ pkgs, ... }:
# Unique setup for j2 laptop
{
  # Enable printing service
  services.printing.enable = true;

  hardware.graphics.enable = true;

  services.xserver.videoDrivers = [ "displaylink" ];

  # Allow unfree drivers as needed
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "displaylink" # for docking station
      "evdi"
    ];
}
