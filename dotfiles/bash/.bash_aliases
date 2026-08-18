#
# General development =============================


vim() {
  if command -v nvim >/dev/null 2>&1; then
    nvim "$@"
  else
    command vim "$@"
  fi
}
edit-aliases() {
  local root="${DOTFILES_ROOT:-/etc/nixos}"
  vim "$root/dotfiles/bash/.bash_aliases" && source "$root/dotfiles/bash/.bash_aliases"
}
alias docker-ps='docker ps -a --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"'
alias myip='curl ifconfig.me'
alias zen='zen-beta'

# get current branch name if in a git repo
git_current_branch() {
    git rev-parse --git-dir >/dev/null 2>&1 || return 0

    local branch

    branch=$(git branch --show-current 2>/dev/null)

    if [[ -z "$branch" ]]; then
        branch=$(git rev-parse --short HEAD 2>/dev/null)
    fi

    if [[ -z "$branch" ]]; then
        branch="no-commits"
    fi

    printf ' (%s) ' "$branch"
}

git_current_branch_short() {
    git rev-parse --git-dir >/dev/null 2>&1 || return 0

    local branch

    branch=$(git branch --show-current 2>/dev/null)

    if [[ -z "$branch" ]]; then
        branch=$(git rev-parse --short HEAD 2>/dev/null)
    fi

    if [[ -z "$branch" ]]; then
        branch="no-commits"
    fi

    printf ' (%.8s) ' "$branch"
}

# Get if dev shell is active
function __dev_shell_prompt() {
  if [ -n "$NIX_DEV_SHELL_NAME" ]; then
    printf "[%s] " "$NIX_DEV_SHELL_NAME"
  fi
}

__dev_shell_prompt_short() {
    if [[ -n "$NIX_DEV_SHELL_NAME" ]]; then
        printf '[%.8s] ' "$NIX_DEV_SHELL_NAME"
    fi
}

export PS1='\n\[\033[1;34m\]$(__dev_shell_prompt_short)\[\033[1;32m\][\[\e]0;\u@\h: \W\a\]\u@\h:\W]\[\033[1;33m\]$(git_current_branch_short)\[\033[1;32m\]\$\[\033[0m\] '

# if I need an even shorter PS1
# export PS1='\n\[\033[1;34m\]$(__dev_shell_prompt_short)\[\033[1;32m\]\W\[\033[1;33m\]$(git_current_branch_short)\[\033[0m\]\$ '

alias codex-danger='codex --dangerously-bypass-approvals-and-sandbox'
alias co='codex-danger'
last-cost-co() {
  uv run python "${DOTFILES_ROOT:-/etc/nixos}/scripts/codex-last-cost.py" "$@"
}

last-cost-pi() {
  uv run python "${DOTFILES_ROOT:-/etc/nixos}/scripts/pi-last-cost.py" "$@"
}

# Browsing ===================================

# temp profile browsing for choem to avoid needing to manually
# override security policies on a persistent chrome profile
alias workaround-tmp-chromium='chromium --user-data-dir="$(mktemp -d)"'

# NixOS =========================================

alias n-build="sudo nixos-rebuild build --flake .#j2 --max-jobs 2 --cores 4"
alias n-dry-build="sudo nixos-rebuild dry-build --flake .#j2"

# check nixos config syntax
alias n-check="nix config check"

# build and set as default boot but don't activate it rn
alias n-boot="sudo nixos-rebuild boot --flake .#j2"

# build and activate this gen rn, but dont make it default boot yet
alias n-test="sudo nixos-rebuild test --flake .#j2"

# build, activate it, and make default boot
alias n-switch="sudo nixos-rebuild switch --flake .#j2 --max-jobs 2 --cores 4"

# Reconcile the live home-directory links without rebuilding NixOS.
dotfiles-stow() {
  "${DOTFILES_ROOT:-/etc/nixos}/scripts/stow-dotfiles.sh" "$@"
}

dotfiles-stow-dry-run() {
  "${DOTFILES_ROOT:-/etc/nixos}/scripts/stow-dotfiles.sh" --dry-run "$@"
}

dotfiles-unstow() {
  "${DOTFILES_ROOT:-/etc/nixos}/scripts/stow-dotfiles.sh" --delete "$@"
}

# Download nixpkgs
alias n-update="nix flake update" # use sudo if /etc/nixos not owned by user
alias n-update-subset="nix flake update nixpkgs home-manager"

# Misc apps =======================================

alias career-ops-codex="/home/saleh/apps/career-ops/scripts/start-codex-career-ops"
alias career-ops-opencode="cd /home/saleh/apps/career-ops && opencode"
alias career-ops="career-ops-codex"

# Misc notes ==============================
# wireplumber failing around ALSA device handling causing CPU to overheat?
# Do `systemctl --user restart wireplumber`
alias workaround-wp="systemctl --user restart wireplumber"

# Recover the MediaTek MT7922 if mt7921e stops scanning or associating.
alias workaround-wifi='sudo modprobe -r mt7921e && sudo modprobe mt7921e && sleep 3 && nmcli device wifi rescan ifname wlp2s0 && nmcli -f SSID,SIGNAL,SECURITY device wifi list ifname wlp2s0'

# workaround loss of tmux bindings
# `tmux detach` then `tmux a`
# `printf '\033c'`
# `reset`
# `tmux refresh-client`
