{ inputs, pkgs, lib, dotfilesRoot, ... }:

let
  captureMonitor = pkgs.writeShellApplication {
    name = "capture-target-monitor";
    runtimeInputs = [ pkgs.nodejs_24 pkgs.pipewire pkgs.inotify-tools ];
    text = ''
      exec node ${lib.escapeShellArg "${dotfilesRoot}/dotfiles/noctalia/.local/share/noctalia/plugins/capture-target/monitor.mjs"} "$@"
    '';
  };
in

{
  programs.noctalia = {
    enable = true;
    systemd.enable = false;
    package = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  };

  # Noctalia's appearance-only GTK hook uses gsettings to publish its theme
  # mode through the desktop portal for applications such as Chromium and
  # Ghostty.
  home.packages = [ pkgs.glib captureMonitor ];

  # Keep the editable monitor and its runtime dependencies available to Noctalia
  # without relying on the environment inherited by the graphical session.
  home.file.".local/bin/capture-target-monitor".source = lib.getExe captureMonitor;
}
