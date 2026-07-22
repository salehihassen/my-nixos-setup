{ config, pkgs, inputs, username ? "saleh", ... }:

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

  programs.bash = {
    enable = true;

    bashrcExtra = ''
      if [ -f "$HOME/.bash_secrets" ]; then
        . "$HOME/.bash_secrets"
      fi

      source ~/.bash_aliases
    '';
  };

  programs.home-manager.enable = true;
  programs.direnv.enable = true;
  # home.file.".config/wallpapers/traffic-blur.jpg".source =
  #  ../../assets/wallpapers/traffic-blur.jpg;

  # home.file.".config/wallpapers/horizon.jpg".source =
  #   ../../assets/wallpapers/horizon.jpg;
  home.file.".bash_aliases".source = ./dotfiles/bash/bash_aliases;
  xdg.configFile."niri/config.kdl".source = ./dotfiles/niri/config.kdl;

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
    NPM_CONFIG_PREFIX = "${config.home.homeDirectory}/.npm-global";
  };

  home.sessionPath = [
    "${config.home.homeDirectory}/.npm-global/bin"
  ];

  home.packages = with pkgs; [
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
  ];

  programs.tmux = {
    enable = true;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      resurrect
      continuum
    ];
    # Keep tmux settings in portable, native tmux syntax.
    extraConfig = builtins.readFile ./dotfiles/tmux.conf;
  };

  programs.git = {
    enable = true;
    settings.user = {
      email = "";
      name = "Saleh Hassen";
    };
    settings = {
      init.defaultBranch = "main";
      safe.directory = "/etc/nixos";
    };
  };

  programs.ghostty = {
    enable = true;
  };

  programs.neovim = {
    enable = true;
    withRuby = false;
    withPython3 = false;
    extraConfig = ''
      set number relativenumber
    '';
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
