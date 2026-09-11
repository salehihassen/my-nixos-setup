{ pkgs, ... }:

{
  home.packages = with pkgs; [
    # Browsers and communication
    chromium
    discord

    # Backups
    borgbackup

    # Terminals and desktop helpers
    alacritty
    wezterm
    swaybg
    wl-clipboard
    pamixer
    pavucontrol
    nautilus
    gimp
    networkmanagerapplet
  ];
}
