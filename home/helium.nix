{ inputs, lib, pkgs, ... }:

{
  # Optional trial: importing this module installs Helium for this user.
  home.packages = [
    inputs.helium-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

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
