{
  lib,
  pkgs,
  ...
}:

let
  # Add or remove plugins here. Order matters: Continuum uses Resurrect's
  # save/restore scripts, so it must load after Resurrect.
  plugins = with pkgs.tmuxPlugins; [
    sensible
    resurrect
    continuum
  ];
in
{
  dotfiles.stowPackages = [ "tmux" ];

  home.packages = [
    pkgs.tmux
    pkgs.xclip # Used by the tmux copy-mode binding.
  ];

  # Keep Nix store paths out of the Stow-owned tmux.conf. Home Manager updates
  # this bridge whenever the pinned plugin packages change.
  xdg.configFile."tmux/nix-plugins.conf".text = lib.concatMapStrings (plugin: ''
    run-shell "${plugin.rtp}"
  '') plugins;
}
