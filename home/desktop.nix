{ config, pkgs, inputs, dotfilesRoot, ... }:

let
  desktopControlCrosshair = pkgs.stdenv.mkDerivation {
    pname = "desktop-control-crosshair";
    version = "1";
    src = ../scripts/desktop-control/crosshair.c;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.gtk4 pkgs.gtk4-layer-shell ];
    buildPhase = ''
      $CC "$src" -o desktop-control-crosshair $(pkg-config --cflags --libs gtk4 gtk4-layer-shell-0)
    '';
    installPhase = ''
      install -Dm755 desktop-control-crosshair "$out/bin/desktop-control-crosshair"
    '';
  };
  desktopControlPointer = pkgs.stdenv.mkDerivation {
    pname = "desktop-control-pointer";
    version = "1";
    src = ../scripts/desktop-control/pointer.c;
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.pkg-config pkgs.wayland-scanner ];
    buildInputs = [ pkgs.wayland ];
    buildPhase = ''
      protocol=${pkgs.wlr-protocols}/share/wlr-protocols/unstable/wlr-virtual-pointer-unstable-v1.xml
      wayland-scanner client-header "$protocol" wlr-virtual-pointer-unstable-v1-client-protocol.h
      wayland-scanner private-code "$protocol" pointer-protocol.c
      $CC -I. "$src" pointer-protocol.c -o desktop-control-pointer $(pkg-config --cflags --libs wayland-client)
    '';
    installPhase = ''
      install -Dm755 desktop-control-pointer "$out/bin/desktop-control-pointer"
    '';
  };
in

{
  imports = [
    ./noctalia.nix # Noctalia UIs
    inputs.zen-browser.homeModules.beta # For Zen browser
  ];

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
    NAUTILUS_4_EXTENSION_DIR = "${pkgs.nautilus-python}/lib/nautilus/extensions-4";
  };

  home.packages = with pkgs; [
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

  systemd.user.services.desktop-control = {
    Unit = {
      Description = "Approved local desktop controls for AI harnesses";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.nodejs_24}/bin/node ${dotfilesRoot}/scripts/desktop-control/service.mjs";
      Environment = [
        "NIRI_BIN=${pkgs.niri}/bin/niri"
        "GRIM_BIN=${pkgs.grim}/bin/grim"
        "YDOTOOL_BIN=${pkgs.ydotool}/bin/ydotool"
        "YDOTOOL_SOCKET=/run/ydotoold/socket"
        "FUZZEL_BIN=${pkgs.fuzzel}/bin/fuzzel"
        "CROSSHAIR_BIN=${desktopControlCrosshair}/bin/desktop-control-crosshair"
        "POINTER_BIN=${desktopControlPointer}/bin/desktop-control-pointer"
        "WLRCTL_BIN=${pkgs.wlrctl}/bin/wlrctl"
        "NOTIFY_BIN=${pkgs.libnotify}/bin/notify-send"
      ];
      Restart = "no";
    };
  };

  home.file.".pi/agent/extensions/desktop-control.ts".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/scripts/desktop-control/pi-extension.ts";

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
