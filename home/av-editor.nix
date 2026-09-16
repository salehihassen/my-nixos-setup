{ pkgs, ... }:

{
  home.packages = with pkgs; [
    kdePackages.kdenlive
    mpv
    tenacity

    # TODO: Try openshot-qt and davinci-resolve as alternative video editors.
  ];
}
