{ inputs, lib, pkgs, ... }:

let
  screencastBus = pkgs.runCommandCC "helium-screencast-bus" {
    nativeBuildInputs = [ pkgs.pkg-config ];
    buildInputs = [ pkgs.glib ];
  } ''
    mkdir -p "$out/lib"
    "$CC" -shared -fPIC -O2 -Wall -Wextra -Werror \
      $(pkg-config --cflags gio-2.0) ${../scripts/helium-screencast-bus.c} \
      $(pkg-config --libs gio-2.0) -o "$out/lib/helium-screencast-bus.so"
  '';
  helium = inputs.helium-browser.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.patchelf ];
    postFixup = (old.postFixup or "") + ''
      patchelf --add-needed ${screencastBus}/lib/helium-screencast-bus.so "$out/opt/helium/helium"
    '';
  });
in
{
  # Optional trial: importing this module installs Helium for this user.
  home.packages = [ helium ];

  xdg.mimeApps = {
    enable = true;
    # Override the desktop/J2 browser defaults only. Keep custom URL handlers
    # (including claude-cli) and agent-specific browser configuration intact.
    defaultApplications = lib.genAttrs [
      "text/html"
      "application/xhtml+xml"
      "application/x-extension-htm"
      "application/x-extension-html"
      "application/x-extension-shtml"
      "application/x-extension-xhtml"
      "application/x-extension-xht"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "x-scheme-handler/about"
      "x-scheme-handler/unknown"
      "x-scheme-handler/chrome"
    ] (_: lib.mkForce [ "helium.desktop" ]);
  };
}
