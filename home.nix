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
  
  home.packages = with pkgs; [
    htop
    ripgrep
    fd
    jq
    unzip
    git
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

  programs.fuzzel = {
    enable = true;
  };
        
  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  };
}
