{ pkgs, ... }:

{
  # Import this directory on hosts that should have the Boat.dev CLI.
  environment.systemPackages = [ (pkgs.callPackage ./package.nix { }) ];
}
