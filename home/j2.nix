{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Browsers and communication
    chromium
    discord

    # Terminals and desktop helpers
    alacritty
    wezterm
    swaybg
    wl-clipboard
    pamixer
    pavucontrol
    nautilus
    networkmanagerapplet
  ];
}
