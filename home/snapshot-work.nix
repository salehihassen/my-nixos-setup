{
  config,
  lib,
  pkgs,
  dotfilesRoot ? null,
  ...
}:

let
  cfg = config.programs.snapshot-work;
  source =
    if cfg.sourceMode == "checkout" then
      "${dotfilesRoot}/scripts/snapshot-work"
    else
      "${../scripts/snapshot-work}";
  captureWork = pkgs.writeShellApplication {
    name = "capture-work";
    runtimeInputs = [
      pkgs.niri
      pkgs.grim
      pkgs.wl-clipboard
      pkgs.ydotool
    ];
    text = ''
      script=${lib.escapeShellArg "${source}/capture.mjs"}
      if [[ ! -r "$script" ]]; then
        printf 'Capture script is missing: %s\nCheck dotfilesRoot or use store sourceMode.\n' "$script" >&2
        exit 1
      fi
      ${lib.optionalString (config.home.sessionVariables ? YDOTOOL_SOCKET) ''
        if [[ ! -v YDOTOOL_SOCKET ]]; then
          export YDOTOOL_SOCKET=${lib.escapeShellArg (toString config.home.sessionVariables.YDOTOOL_SOCKET)}
        fi
      ''}
      exec ${pkgs.nodejs_24}/bin/node "$script" "$@"
    '';
  };
  legacyLauncher = pkgs.writeText "legacy-capture-work" ''
    #!/usr/bin/env bash
    set -euo pipefail
    exec node "$HOME/.local/share/work-capture/capture.mjs" "$@"
  '';
in
{
  options.programs.snapshot-work.sourceMode = lib.mkOption {
    type = lib.types.enum [
      "store"
      "checkout"
    ];
    default = "store";
    description = "Run the packaged snapshot source, or editable source at dotfilesRoot.";
  };

  config = {
    assertions = [
      {
        assertion =
          cfg.sourceMode != "checkout"
          || (dotfilesRoot != null && lib.hasPrefix "/" dotfilesRoot && dotfilesRoot != "/");
        message = "snapshot-work checkout mode requires an absolute dotfilesRoot.";
      }
    ];
    home.packages = [ captureWork ];
    # Preserve the original command path as well as installing it in the profile.
    home.file.".local/bin/capture-work".source = lib.getExe captureWork;
    # Only migrate the exact launcher created before this module existed.
    # Unknown files remain subject to Home Manager's normal conflict checks.
    home.activation.migrateLegacyCaptureWork = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      legacy=${lib.escapeShellArg "${config.home.homeDirectory}/.local/bin/capture-work"}
      if [[ -f "$legacy" && ! -L "$legacy" ]] && ${pkgs.diffutils}/bin/cmp -s "$legacy" ${legacyLauncher}; then
        if [[ -e "$legacy.pre-home-manager" || -L "$legacy.pre-home-manager" ]]; then
          echo "Refusing to overwrite $legacy.pre-home-manager; move the legacy launcher aside manually." >&2
          exit 1
        fi
        run ${pkgs.coreutils}/bin/mv -- "$legacy" "$legacy.pre-home-manager"
      fi
    '';
  };
}
