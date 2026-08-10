# NixOS configuration

This repository is the canonical configuration checkout at `/etc/nixos`.
NixOS and Home Manager manage packages, services, plugins, generated integration
files, and environment variables. GNU Stow manages editable user preferences, so
editing a tracked dotfile changes the live configuration immediately.

## Dotfile layout

Each directory directly below `dotfiles/` is a Stow package whose contents mirror
paths relative to `$HOME`:

```text
dotfiles/
├── bash/{.bashrc,.bash_profile,.profile,.bash_aliases}
├── git/.config/git/config
├── neovim/.config/nvim/{init.lua,init.vim}
├── niri/.config/niri/
├── noctalia/.config/noctalia/config.toml
├── ssh/.ssh/config
├── tmux/.config/tmux/tmux.conf
└── wallpapers/.config/wallpapers/
```

Private files, SSH keys, `~/.ssh/config.local`, and `~/.bash_secrets` stay local
and untracked. The Bash package explicitly ignores `bash_secrets` and never
manages the live `~/.bash_secrets`.

Stow always runs with `--no-folding`, producing file-level links that can coexist
with Home Manager files in `.config`, `.local`, and `.ssh`.

## Bootstrap and reconciliation

The first NixOS activation installs Stow and runs the helper after Home Manager's
old file links are removed:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#j2
```

After that, reconcile links manually with:

```bash
dotfiles-stow
```

Check for conflicts without changing links:

```bash
dotfiles-stow-dry-run
```

The aliases call `/etc/nixos/scripts/stow-dotfiles.sh`. That helper is the single
source of truth for the managed package list and refuses missing, symlinked, or
unsafe source and target directories. It never uses `stow --adopt`; resolve any
reported conflict deliberately before restowing.

## Add a Stow package

1. Create `dotfiles/<package>/`.
2. Inside it, reproduce the path relative to `$HOME`. For example,
   `dotfiles/zed/.config/zed/settings.json` maps to
   `~/.config/zed/settings.json`.
3. Add `<package>` to the `packages` array in
   `scripts/stow-dotfiles.sh`.
4. Remove any Home Manager `home.file`, `xdg.configFile`, or program-module
   declaration that owns the same destination. Keep the application package and
   integrations declarative where possible.
5. Run `dotfiles-stow-dry-run`, then `dotfiles-stow`.

## Rollback

Remove all Stow-managed links first:

```bash
dotfiles-unstow
```

Then activate the previous NixOS generation so its Home Manager generation can
reclaim the old destinations. `--delete` removes only managed links; it does not
delete the tracked source files or local secrets.

## Machine setup still required

- Download DisplayLink drivers when prompted during a build.
- Generate or copy SSH keys and any machine-local SSH configuration.
- Adjust the configured username if it is not `saleh`.
- Set the user password with `passwd`.
