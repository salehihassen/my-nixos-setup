{ pkgs, ... }:

{
  home.packages = with pkgs; [
    home-assistant-cli

    # Browsers and communication
    chromium
    discord

    # Backups
    borgbackup

    # Keyboard firmware
    qmk
    dos2unix

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
