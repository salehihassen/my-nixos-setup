{ pkgs, ... }:

{
  imports = [ ./t3code.nix ];

  programs.snapshot-work.sourceMode = "checkout";
  home.sessionVariables.YDOTOOL_SOCKET = "/run/ydotoold/socket";

  home.packages = with pkgs; [
    home-assistant-cli

    # Browsers and communication
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
    pamixer
    pavucontrol
    gimp
    networkmanagerapplet
  ];
}
