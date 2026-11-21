#!/usr/bin/env bash
# Adopt the portable Home Manager profile on this non-NixOS machine as the
# current user, then check that tmux, its plugins and save/restore work.
# Only for disposable CI machines: it moves conflicting dotfiles aside.
set -euo pipefail

if [[ "${CI:-}" != true ]]; then
  echo 'Refusing to run outside CI (CI=true): this replaces dotfiles in $HOME.' >&2
  exit 1
fi

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
user="$(id -un)"
export USER="$user" TERM=xterm-256color

fail() {
  echo "::error::$*"
  exit 1
}

# Retry a command for up to ~15 seconds; tmux plugins and restores run async.
wait_until() {
  local message="$1" attempt
  shift
  for ((attempt = 0; attempt < 75; attempt++)); do
    "$@" && return 0
    sleep 0.2
  done
  fail "$message"
}

home_args=(
  --impure
  --file "$repo_root/.github/ci/portable-home.nix"
  --argstr repo "$repo_root"
  --argstr user "$user"
  --argstr home "$HOME"
)

echo "::group::Build portable Home Manager profile for $user"
activation="$(nix build "${home_args[@]}" activationPackage --no-link --print-out-paths -L)"
stow_packages="$(nix eval "${home_args[@]}" --raw config.home.sessionVariables.DOTFILES_STOW_PACKAGES)"
echo '::endgroup::'

echo "::group::Activate (Stow packages: $stow_packages)"
# A fresh machine already has some of these files (e.g. ~/.bashrc). The README
# asks users to back them up first; do the same so Stow can link the checkout.
for package in $stow_packages; do
  while IFS= read -r path; do
    target="$HOME/$path"
    if [[ -e "$target" && ! -L "$target" ]]; then
      mv -- "$target" "$target.pre-dotfiles"
      echo "Moved aside existing $target"
    fi
  done < <(cd "$repo_root/dotfiles/$package" && find . \( -type f -o -type l \) -printf '%P\n')
done
HOME_MANAGER_BACKUP_EXT=pre-hm "$activation/activate"
echo '::endgroup::'

echo '::group::Check tmux configuration'
tmux="$HOME/.nix-profile/bin/tmux"
config="$HOME/.config/tmux/tmux.conf"
[[ -x "$tmux" ]] || fail "Home Manager did not install tmux at $tmux"
"$tmux" -V
[[ "$(readlink -f "$config")" == "$repo_root/dotfiles/tmux/.config/tmux/tmux.conf" ]] ||
  fail "Stow did not link $config to the checkout"
[[ -s "$HOME/.config/tmux/nix-plugins.conf" ]] || fail 'Home Manager did not generate nix-plugins.conf'

"$tmux" new-session -d -s ci -c /tmp
"$tmux" new-window -t ci -c "$HOME"
plugins_loaded() { [[ -n "$("$tmux" show -gqv @resurrect-save-script-path)" ]]; }
wait_until 'Resurrect did not load' plugins_loaded
# A reload must not report errors or drop Continuum's autosave hook.
"$tmux" source-file "$config" || fail 'Reloading tmux.conf reported errors'
[[ "$("$tmux" show -gv status-right)" == *continuum_save.sh* ]] || fail 'Continuum autosave hook is missing'
[[ "$("$tmux" show -gv extended-keys)" == on ]] || fail 'extended-keys is not on'
[[ "$("$tmux" show -gv extended-keys-format)" == csi-u ]] || fail 'extended-keys-format is not csi-u'
echo '::endgroup::'

echo '::group::Check save and restore across a simulated reboot'
"$("$tmux" show -gqv @resurrect-save-script-path)" quiet
grep -q $'^pane\tci\t' "$HOME/.tmux/resurrect/last" || fail 'Resurrect did not save session ci'
"$tmux" kill-server
no_tmux_running() { ! pgrep -u "$user" -x tmux >/dev/null; }
wait_until 'tmux server did not exit' no_tmux_running

# A new server is what the first `tmux` after a reboot starts.
"$tmux" new-session -d -s fresh
wait_until 'Continuum did not auto-restore session ci' "$tmux" has-session -t ci
[[ "$("$tmux" list-windows -t ci | wc -l)" -eq 2 ]] || fail 'Restored session ci does not have 2 windows'
[[ "$("$tmux" display -p -t ci:0 '#{pane_current_path}')" == /tmp ]] ||
  fail 'Restored pane is not in /tmp'
"$tmux" kill-server
echo '::endgroup::'

echo 'Portable home activated; tmux plugins, reload and save/restore work.'
