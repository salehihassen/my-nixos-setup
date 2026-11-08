# Named workspaces

The existing Fuzzel launcher provides on-demand pickers for niri's native
workspace names. No background service is needed.

| Shortcut | Action |
| --- | --- |
| `Mod+Alt+G` | Search named workspaces across monitors and switch to one. |
| `Mod+Ctrl+Alt+G` | Move the focused column, including all stacked/tabbed windows, to a named workspace and follow it. |
| `Mod+Shift+Alt+G` | Open the current workspace's name and monitor management menu. |

To add a named workspace, navigate to the bottom empty workspace and name it.
You can also name an existing workspace. Enter applies a name; Escape or an
empty name cancels. Existing names are prefilled when renaming. Names must be
unique, single-line nicknames and cannot consist only of digits.

The management menu always offers Name or Rename. Named workspaces also have
Remove name / return to dynamic. When at least two displays are enabled, the
menu includes Move workspace to monitor on left/right. These move the entire
workspace, including its name and every column. The move entries are hidden
with a single display; connected but disabled displays do not count. If a
display disconnects while the menu is open, the helper checks again before
moving. Naming an unnamed workspace now starts with the menu's Name entry.

Remove name returns the workspace to niri's normal dynamic behavior. Windows
remain open; an empty workspace can disappear when you leave it. Names created
by these shortcuts last until niri exits. They are not written into the config.

Existing shortcuts still apply: `Mod+Shift+I/U` reorders the workspace,
`Mod+Ctrl+I/U` moves columns between adjacent workspaces, and `Mod+W` toggles
tabbed display. Positional number shortcuts remain available.

Noctalia shows workspace names, truncated to 16 characters with its full-name
tooltip available on hover. The helper lives in
`dotfiles/misc-scripts/niri-workspace`, linked by the existing Stow package as
`~/niri-workspace`.

Validate without opening popups or moving windows:

```bash
bash -n dotfiles/misc-scripts/niri-workspace
node scripts/test-niri-workspace.mjs
niri validate
noctalia config validate
```

The isolated checks model Fuzzel's launcher versus dmenu behavior: name textboxes
must explicitly use `--dmenu`, or Fuzzel tries to launch an application instead
of returning the typed name. The checks never open popups or move real windows.
