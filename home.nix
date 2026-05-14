{ config, pkgs, inputs, ... }: 

{
  imports = [
    inputs.noctalia.homeModules.default
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

  programs.git = {
    enable = true;
    userName = "Saleh Hassen";
    userEmail = "";
  };

  programs.ghostty = {
    enable = true;
  };

  programs.fuzzel = {
    enable = true;
  };

  programs.noctalia-shell = {
    enable = true;

    settings = {
      bar = {
        position = "top";
        density = "default";

        widgets = {
          left = [
            {
              id = "ControlCenter";
              useDistroLogo = true;
            }
          ];

          center = [
            {
              id = "Workspace";
              hideUnoccupied = false;
              labelMode = "none";
            }
          ];

          right = [
            {
              id = "Network";
            }
            {
              id = "Battery";
              warningThreshold = 30;
            }
            {
              id = "Clock";
              formatHorizontal = "HH:mm";
              useMonospacedFont = true;
            }
          ];
        };
      };
    };
  };

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  };
}
