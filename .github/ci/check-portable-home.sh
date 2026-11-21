#!/usr/bin/env bash
set -euo pipefail

[[ "${CI:-}" == true ]] || { echo 'Refusing to run outside CI (CI=true).' >&2; exit 1; }

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
HOME="$(mktemp -d)"
USER="$(id -un)"
export HOME USER

home="(builtins.getFlake \"git+file://$repo\").lib.mkStandaloneHome {
  username = \"$USER\"; homeDirectory = \"$HOME\"; dotfilesRoot = \"$repo\";
}"
activation="$(nix build --impure --no-link --print-out-paths -L --expr "($home).activationPackage")"
"$activation/activate"

"$HOME/.nix-profile/bin/tmux" -V
for plugin in sensible resurrect continuum; do
  test -f "$(grep -o "/nix/store/[^\"]*/$plugin\.tmux" "$HOME/.config/tmux/nix-plugins.conf")"
  echo "tmux plugin installed: $plugin"
done
