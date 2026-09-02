{ config, pkgs, inputs, ... }:

{
  imports = [
    ./home/portable.nix # Portable CLI and editable dotfiles
    #inputs.noctalia.homeModules.default
    ./home/noctalia.nix # Noctalia UIs
    inputs.zen-browser.homeModules.beta # For Zen browser
  ];

  home.sessionVariables = {
    MOZ_ENABLE_WAYLAND = "1";
    NIXOS_OZONE_WL = "1";
  };

  home.packages = with pkgs; [
    zed-editor
    wf-recorder
    slurp
    grim
    drawio
    qbittorrent
    remmina
    freerdp
    kdePackages.kcalc
  ];

  programs.ghostty = {
    enable = true;
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
    musicDirectory = "${config.home.homeDirectory}/Music";
    # Optional:
    network.listenAddress = "any"; # if you want to allow non-localhost connections
    network.startWhenNeeded = true; # systemd feature: only start MPD service upon connection to its socket
  };
  # TODO, if rclone/rclone.conf is present in the nixos configs (gitignored and excluded from repo), use it as rclone config?


}
