{ pkgs, ... }: {
  home.username = "saleh";
  home.homeDirectory = "/home/saleh";
  home.stateVersion = "25.11";

  home.packages = [ pkgs.htop pkgs.git ];
  programs.bash.enable = true;
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    htop
    ripgrep
    fd
    jq
    unzip
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

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  };
}
