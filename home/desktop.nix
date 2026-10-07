{
  config,
  lib,
  pkgs,
  inputs,
  dotfilesRoot,
  ...
}:

let
  nautilus = pkgs.symlinkJoin {
    name = "nautilus-with-ghostty";
    paths = [ pkgs.nautilus ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/nautilus" \
        --set NAUTILUS_4_EXTENSION_DIR "${pkgs.nautilus-python}/lib/nautilus/extensions-4" \
        --set GSK_RENDERER gl
      # D-Bus activation must use the same launcher as Mod + E.
      service=share/dbus-1/services/org.gnome.Nautilus.service
      rm "$out/$service"
      substitute "${pkgs.nautilus}/$service" "$out/$service" \
        --replace-fail "${pkgs.nautilus}/bin/nautilus" "$out/bin/nautilus"
    '';
  };
in

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
  };

  home.packages = with pkgs; [
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
  ];

  # Ghostty ships an "Open in Ghostty" menu extension for Nautilus.
  xdg.dataFile."nautilus-python/extensions/ghostty.py".source =
    "${config.programs.ghostty.package}/share/nautilus-python/extensions/ghostty.py";

  # Ghostty's editable preferences are managed by GNU Stow.
  programs.ghostty.enable = true;
  programs.fuzzel.enable = true;

  programs.zen-browser = {
    enable = true;
    setAsDefaultBrowser = true;
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
