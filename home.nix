{ config, pkgs, inputs, ... }: 

{
  imports = [
    #inputs.noctalia.homeModules.default
    ./home/noctalia.nix # Noctalia UIs
    ./home/ssh.nix # Ssh agent and ssh configs
  ];

  home.username = "saleh";
  home.homeDirectory = "/home/saleh";
  home.stateVersion = "25.11";

  programs.bash.enable = true;
  programs.home-manager.enable = true;

  # home.file.".config/wallpapers/traffic-blur.jpg".source =
  #  ../../assets/wallpapers/traffic-blur.jpg;

  # home.file.".config/wallpapers/horizon.jpg".source =
  #   ../../assets/wallpapers/horizon.jpg;

  home.packages = with pkgs; [
    htop
    ripgrep
    fd
    jq
    unzip
    git
    nodejs_24
  ];

  programs.tmux = {
    enable = true;
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
    extraConfig = ''
      set number relativenumber
    '';
  };

  programs.fuzzel = {
    enable = true;
  };

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  };

}
