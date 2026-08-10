{ config, lib, pkgs, inputs, username ? "saleh", ... }:

{
  imports = [
    #inputs.noctalia.homeModules.default
    ./home/noctalia.nix # Noctalia UIs
    ./home/ssh.nix # Ssh agent and ssh configs
    inputs.zen-browser.homeModules.beta # For Zen browser
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "25.11";

  programs.home-manager.enable = true;
  programs.direnv.enable = true;

  # Home Manager removes links from the previous generation first, then Stow
  # reconciles the editable files kept under /etc/nixos/dotfiles.
  home.activation.stowDotfiles = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    export HOME=${lib.escapeShellArg config.home.homeDirectory}
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.stow ]}:$PATH
    ${./scripts/stow-dotfiles.sh}
  '';

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
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
    htop
    ripgrep
    fd
    jq
    unzip
    git
    nodejs_24
    pnpm
    bubblewrap
    zed-editor
    rclone
    bind
    openssl
    wf-recorder
    slurp
    grim
    drawio
    wakeonlan
    qbittorrent
    xclip # Used by the tmux copy-mode binding.
    remmina
    freerdp
    
    # AI / Coding Harness
    claude-code

  ];

  programs.ghostty = {
    enable = true;
  };

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

    # Plugins and the wrapped package stay declarative. Stow supplies init.lua
    # and init.vim, so Home Manager must not create $XDG_CONFIG_HOME/nvim/init.lua.
    sideloadInitLua = true;
    # Selecting init.lua explicitly avoids Neovim's automatic-discovery warning
    # when both init.lua and the sourced init.vim are present.
    extraWrapperArgs = [
      "--add-flags"
      "-u ${config.xdg.configHome}/nvim/init.lua"
    ];
  };

  programs.fuzzel = {
    enable = true;
  };

  programs.zen-browser = {
    enable = true;
    setAsDefaultBrowser = true;
  };

  services.mpd = {
    enable = true;
    musicDirectory = "/home/saleh/Music";
    # Optional:
    network.listenAddress = "any"; # if you want to allow non-localhost connections
    network.startWhenNeeded = true; # systemd feature: only start MPD service upon connection to its socket
  };
  # TODO, if rclone/rclone.conf is present in the nixos configs (gitignored and excluded from repo), use it as rclone config?


}
