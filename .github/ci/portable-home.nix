# The portable Home Manager profile for the current non-NixOS user, built the
# same way the README's homeConfigurations entry builds it.
{
  repo,
  user,
  home,
}:
(builtins.getFlake "git+file://${repo}").lib.mkStandaloneHome {
  username = user;
  homeDirectory = home;
  dotfilesRoot = repo;
}
