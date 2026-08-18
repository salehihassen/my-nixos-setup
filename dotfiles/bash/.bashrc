# Load machine-local secrets before interactive-only setup.
if [ -f "$HOME/.bash_secrets" ]; then
  . "$HOME/.bash_secrets"
fi

if [ -f "$HOME/.bash_aliases" ]; then
  . "$HOME/.bash_aliases"
fi

# Commands below this point apply only to interactive shells.
[[ $- == *i* ]] || return

HISTFILESIZE=100000
HISTSIZE=10000

shopt -s histappend
shopt -s extglob
shopt -s globstar
shopt -s checkjobs

for bash_completion in \
  "/etc/profiles/per-user/${USER}/share/bash-completion/bash_completion" \
  "$HOME/.nix-profile/share/bash-completion/bash_completion"
do
  if [[ ! -v BASH_COMPLETION_VERSINFO && -r "$bash_completion" ]]; then
    . "$bash_completion"
    break
  fi
done
unset bash_completion

if [[ -n "${GHOSTTY_RESOURCES_DIR:-}" ]]; then
  ghostty_integration="${GHOSTTY_RESOURCES_DIR}/shell-integration/bash/ghostty.bash"
  if [[ -r "$ghostty_integration" ]]; then
    . "$ghostty_integration"
  fi
  unset ghostty_integration
fi

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
fi
