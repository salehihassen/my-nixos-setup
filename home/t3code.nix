{ config, lib, pkgs, inputs, dotfilesRoot, ... }:
let
  cfg = config.services.t3code;
  providerPath = lib.makeBinPath cfg.providerPackages;
  pairing = pkgs.writeShellApplication {
    name = "t3code-pair";
    runtimeInputs = [ pkgs.nodejs_24 ];
    text = ''
      export T3CODE_BINARY=${lib.escapeShellArg "${cfg.package}/bin/t3"}
      export T3CODE_HOME=${lib.escapeShellArg cfg.dataDirectory}
      exec node ${lib.escapeShellArg "${dotfilesRoot}/scripts/t3code-pair.mjs"} "$@"
    '';
  };
in {
  imports = [ inputs.t3-code-nix.homeModules.t3code ];

  services.t3code = {
    enable = true;
    # Change these two values to select stable/nightly and source/prebuilt.
    channel = "stable";
    packageVariant = "prebuilt";
    host = "127.0.0.1";
    port = 3773;
    dataDirectory = "${config.home.homeDirectory}/.t3";
    workingDirectory = config.home.homeDirectory;
    providerPackages = with pkgs; [
      git
      nodejs_24
      bash
      openssh
      ripgrep
      procps
      bubblewrap
      socat
    ];
  };

  home.packages = [ cfg.package pairing ];

  # Claude Code and Codex are installed with npm under the user's prefix.
  # Keep them ahead of the declarative provider tools and normal profile paths.
  systemd.user.services.t3code = {
    Unit.StartLimitIntervalSec = 0;
    Service = {
      Environment = lib.mkForce [
        "PATH=%h/.npm-global/bin:${providerPath}:%h/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin:/run/wrappers/bin"
        "T3CODE_DISABLE_AUTO_UPDATE=1"
      ];
      UMask = "0077";
    };
  };
}
