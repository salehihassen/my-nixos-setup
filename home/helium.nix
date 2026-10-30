{ inputs, pkgs, ... }:

{
  # Optional trial: importing this module installs Helium for this user.
  home.packages = [
    inputs.helium-browser.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
