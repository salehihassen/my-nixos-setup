# Full portable profile: the lightweight core plus development tooling.
# Servers that only need debugging tools import portable-core.nix instead.
{
  imports = [
    ./portable-core.nix
    ./portable-dev.nix
  ];
}
