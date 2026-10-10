{
  config,
  lib,
  pkgs,
  inputs,
  dotfilesRoot,
  ...
}:

{
  imports = [
    ./noctalia.nix # Noctalia UIs
    inputs.zen-browser.homeModules.beta # For Zen browser
  ];

  dotfiles.stowPackages = [
    "ghostty"
    "misc-scripts"
    "niri"
    "noctalia"
    "wallpapers"
  ];

  # NixOS owns Niri's system/user units and portals there. Standalone Home
  # Manager supplies user integration without taking ownership of Stow's KDL.
  wayland.windowManager.niri = lib.mkIf config.targets.genericLinux.enable {
    enable = true;
  };
  xdg.portal.extraPortals = lib.mkIf config.targets.genericLinux.enable [
    pkgs.xdg-desktop-portal-gtk
  ];

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  }
  // lib.optionalAttrs config.targets.genericLinux.enable {
    # NixOS supplies this through programs.nautilus-open-any-terminal.
    NAUTILUS_4_EXTENSION_DIR = "${pkgs.nautilus-python}/lib/nautilus/extensions-4";
  };

  home.packages =
    with pkgs;
    [
      niri
      xwayland-satellite
      dbus
      jq
      coreutils
      procps
      orca
      chromium
      wl-clipboard
      kdePackages.polkit-kde-agent-1
      adwaita-icon-theme
      gnome-themes-extra
      nautilus
      zed-editor
      gpu-screen-recorder
      slurp
      grim
      wlrctl
      drawio
      qbittorrent
      remmina
      freerdp
      kdePackages.kcalc
    ]
    ++ lib.optionals config.targets.genericLinux.enable [
      pkgs.nautilus-python
      pkgs.nautilus-open-any-terminal
    ];

  dconf.settings = lib.mkIf config.targets.genericLinux.enable {
    "com/github/stunkymonkey/nautilus-open-any-terminal".terminal = "ghostty";
  };
  xdg.dataFile = lib.mkIf config.targets.genericLinux.enable {
    "nautilus-python/extensions/nautilus_open_any_terminal.py".source =
      "${pkgs.nautilus-open-any-terminal}/share/nautilus-python/extensions/nautilus_open_any_terminal.py";
  };

  # Ghostty's editable preferences are managed by GNU Stow.
  programs.ghostty.enable = true;
  programs.fuzzel.enable = true;

  programs.zen-browser = {
    enable = true;
    setAsDefaultBrowser = false;
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "chromium-browser.desktop";
      "x-scheme-handler/http" = "chromium-browser.desktop";
      "x-scheme-handler/https" = "chromium-browser.desktop";
      "x-scheme-handler/about" = "chromium-browser.desktop";
      "x-scheme-handler/unknown" = "chromium-browser.desktop";
    };
  };

  services.mpd = {
    enable = true;
    musicDirectory = "${config.home.homeDirectory}/Music";
    network.listenAddress = "any";
    network.startWhenNeeded = true;
  };

  # TODO, if rclone/rclone.conf is present in the nixos configs (gitignored
  # and excluded from repo), use it as rclone config?
}
