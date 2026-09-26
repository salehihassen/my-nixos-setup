{ inputs, pkgs, ... }:

{
  programs.noctalia = {
    enable = true;
    systemd.enable = false;
    package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

  # Noctalia's appearance-only GTK hook uses gsettings to publish its theme
  # mode through the desktop portal for applications such as Chromium and
  # Ghostty.
  home.packages = [ pkgs.glib ];
}
