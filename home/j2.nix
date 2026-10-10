{ pkgs, ... }:

{
  imports = [ ./t3code.nix ];

  programs.snapshot-work.sourceMode = "checkout";
  home.sessionVariables.YDOTOOL_SOCKET = "/run/ydotoold/socket";

  # Preserve J2's local associations when Home Manager takes ownership.
  xdg.mimeApps = {
    associations.added = {
      "video/mp4" = "chromium-browser.desktop";
      "application/vnd.openxmlformats-officedocument.presentationml.presentation" =
        "chromium-browser.desktop";
      "x-scheme-handler/http" = "zen-beta.desktop";
      "x-scheme-handler/https" = "zen-beta.desktop";
      "x-scheme-handler/chrome" = "zen-beta.desktop";
      "text/html" = "zen-beta.desktop";
      "application/x-extension-htm" = "zen-beta.desktop";
      "application/x-extension-html" = "zen-beta.desktop";
      "application/x-extension-shtml" = "zen-beta.desktop";
      "application/xhtml+xml" = "zen-beta.desktop";
      "application/x-extension-xhtml" = "zen-beta.desktop";
      "application/x-extension-xht" = "zen-beta.desktop";
    };
    defaultApplications = {
      "x-scheme-handler/chrome" = "zen-beta.desktop";
      "application/x-extension-htm" = "zen-beta.desktop";
      "application/x-extension-html" = "zen-beta.desktop";
      "application/x-extension-shtml" = "zen-beta.desktop";
      "application/xhtml+xml" = "zen-beta.desktop";
      "application/x-extension-xhtml" = "zen-beta.desktop";
      "application/x-extension-xht" = "zen-beta.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
      "x-scheme-handler/web+nextcloudreddit" = "chromium-browser.desktop";
      "x-scheme-handler/webcal" = "chromium-browser.desktop";
    };
  };

  home.packages = with pkgs; [
    home-assistant-cli

    # Browsers and communication
    discord

    # Backups
    borgbackup

    # Games
    steam-run

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
