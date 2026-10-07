# Portable client pieces for approved AI desktop control (computer use):
# the pi extension, the MCP server launcher, and the stop helper.
#
# Safe to import on any machine — including standalone Home Manager on
# non-NixOS Linux. The actual input-injection privilege boundary lives in
# the NixOS module modules/desktop-control.nix; without it, these launchers
# simply have no service to talk to.
{
  config,
  lib,
  pkgs,
  dotfilesRoot,
  ...
}:

let
  # The implementation remains editable; only the launcher/dependencies are frozen.
  checkoutCommand =
    name: interpreter: relativePath: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = ''
        script=${lib.escapeShellArg "${dotfilesRoot}/${relativePath}"}
        if [[ ! -r "$script" ]]; then
          printf 'Checkout script is missing: %s\nCheck dotfilesRoot.\n' "$script" >&2
          exit 1
        fi
        exec ${interpreter} "$script" "$@"
      '';
    };
  desktopControlMcp =
    checkoutCommand "desktop-control-mcp" "${pkgs.nodejs_24}/bin/node" "scripts/desktop-control/mcp.mjs"
      [ ];
  desktopControlStop =
    checkoutCommand "desktop-control-stop" "${pkgs.bash}/bin/bash" "scripts/desktop-control/stop.sh"
      [
        pkgs.systemd
        pkgs.libnotify
      ];
in

{
  home.packages = [
    desktopControlMcp
    desktopControlStop
  ];

  home.file.".pi/agent/extensions/desktop-control.ts".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfilesRoot}/scripts/desktop-control/pi-extension.ts";
}
