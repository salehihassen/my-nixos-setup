{ config, pkgs, inputs, ... }: 

{
  imports = [
    #inputs.noctalia.homeModules.default
    ./home/noctalia.nix
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
      safe.directory = "etc/nixos";
    };
  };

  programs.ghostty = {
    enable = true;
  };

  programs.fuzzel = {
    enable = true;
  };

  services.ssh-agent.enable = true;
  programs.ssh = {
    enable = true;

    matchBlocks = {
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_ed25519.pub";
        addKeysToAgent = "4h";
        identitiesOnly = true;
      };
    };
  };
        
  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  };
}
