{
  config,
  lib,
  pkgs,
  username ? "saleh",
  dotfilesRoot ? "/etc/nixos",
  ...
}:

{
  imports = [
    ./ssh.nix
  ];

  assertions = [
    {
      assertion = lib.hasPrefix "/" dotfilesRoot && dotfilesRoot != "/";
      message = "dotfilesRoot must be an absolute path to the editable configuration checkout";
    }
  ];

  home.username = username;
  home.homeDirectory = lib.mkDefault "/home/${username}";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
  programs.direnv.enable = true;

  # Home Manager owns packages and generated integration files. Stow runs
  # afterwards and owns the editable preferences in the declared checkout.
  home.activation.stowDotfiles = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.stow ]}:$PATH
    ${pkgs.bash}/bin/bash ${lib.escapeShellArg "${dotfilesRoot}/scripts/stow-dotfiles.sh"}
  '';

  home.sessionVariables = {
    DOTFILES_ROOT = dotfilesRoot;
    NPM_CONFIG_PREFIX = "${config.home.homeDirectory}/.npm-global";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.npm-global/bin"
  ];

  home.packages = with pkgs; [
    stow
    bash-completion
    tmux
    tmuxPlugins.sensible
    tmuxPlugins.resurrect
    tmuxPlugins.continuum
    tree
    htop
    ripgrep
    fd
    jq
    ffmpeg
    unzip
    git
    curl
    uv
    nodejs_24
    pnpm
    bubblewrap
    rclone
    bind
    openssl
    wakeonlan
    xclip # Used by the tmux copy-mode binding.
  ];

  # Keep Nix store paths out of the Stow-owned tmux.conf. Home Manager updates
  # this bridge whenever the pinned plugin packages change.
  xdg.configFile."tmux/nix-plugins.conf".text = ''
    run-shell "${pkgs.tmuxPlugins.sensible}/share/tmux-plugins/sensible/sensible.tmux"
    run-shell "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect/resurrect.tmux"
    run-shell "${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum/continuum.tmux"
  '';

  programs.neovim = {
    enable = true;
    withRuby = false;
    withPython3 = false;

    extraPackages = with pkgs; [
      typescript-language-server
    ];

    plugins = [
      pkgs.vimPlugins.nvim-lspconfig
      (pkgs.vimPlugins.nvim-treesitter.withPlugins (p: with p; [
        bash
        javascript
        json
        lua
        markdown
        markdown_inline
        nix
        tsx
        typescript
        vim
        vimdoc
      ]))
    ];

    # Stow supplies init.lua and init.vim, so Home Manager must not create
    # $XDG_CONFIG_HOME/nvim/init.lua.
    sideloadInitLua = true;
    extraWrapperArgs = [
      "--add-flags"
      "-u ${config.xdg.configHome}/nvim/init.lua"
    ];
  };
}
