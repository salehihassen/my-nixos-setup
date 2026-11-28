{
  config,
  pkgs,
  ...
}:

# Development tooling layered on portable-core.nix: language runtimes, media,
# browser automation, and secret scanning. Servers import only the core.
{
  home.sessionVariables.NPM_CONFIG_PREFIX = "${config.home.homeDirectory}/.npm-global";

  home.sessionPath = [
    "${config.home.homeDirectory}/.npm-global/bin"
  ];

  home.packages = with pkgs; [
    ffmpeg
    checkpwn
    gitleaks
    uv
    nodejs_24
    pnpm
    # Expose Playwright's agent CLI with a Nix-managed browser for every harness.
    (writeShellScriptBin "playwright-cli" ''
      export PLAYWRIGHT_MCP_EXECUTABLE_PATH="${pkgs.chromium}/bin/chromium"
      exec ${pkgs.nodejs_24}/bin/node ${pkgs.playwright-driver}/cli.js cli "$@"
    '')
    bubblewrap
    rclone
  ];

  programs.neovim.extraPackages = with pkgs; [
    typescript-language-server
  ];
}
