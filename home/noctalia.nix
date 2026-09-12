{ inputs, pkgs, ... }:

{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  programs.noctalia = {
    enable = true;
    systemd.enable = false;
  };

  # Noctalia's appearance-only GTK hook uses gsettings to publish its theme
  # mode through the desktop portal for applications such as Chromium and
  # Ghostty.
  home.packages = [ pkgs.glib ];
}
