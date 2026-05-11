{ pkgs, ... }: {
  home.username = "saleh";
  home.homeDirectory = "/home/saleh";
  home.stateVersion = "25.11"; # Match your nixos system stateVersion

  home.packages = [ pkgs.htop pkgs.git ];
  programs.bash.enable = true;
  programs.home-manager.enable = true;
}
