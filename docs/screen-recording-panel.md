# Panel B: official Noctalia recorder

This branch removes the custom recording-status plugin and uses Noctalia's
official `noctalia/screen_recorder` plugin, backed by `gpu-screen-recorder`.
The recorder package replaces `wf-recorder` in the desktop Home Manager module.
No upstream plugin scripts are modified or copied into this repository.

Super+Alt+R calls the plugin's singleton service with `toggle`. Starting opens
the desktop portal's monitor/window picker; stopping finalizes the recording.
Videos go to `~/Videos/recording-YYYY-MM-DD_HH-MM-SS.mp4`, without audio.

The official bar widget stays visible while idle (`video-off`) and shows a red
recording glyph (`player-record`) while active. Clicking it toggles recording.
Its current upstream implementation shows a status icon, without the captured
monitor's connector, aliases, filename tooltip, or a `Not recording` text label.
This is an intentional comparison of the stock widget against panel-a.

## Why portal capture

On this machine, `gpu-screen-recorder --info` lists the built-in display for
direct capture but does not list the two DisplayLink-connected displays. Using
`video_source = "focused"` would attempt an unsupported direct capture when one
of those displays is focused. Portal mode allows selecting the docked monitors
and unfamiliar office monitors through Niri's existing desktop portal.

The tradeoff is a picker when starting. It needs the existing
`xdg-desktop-portal` / `xdg-desktop-portal-gnome` services. It does not require
adding a privileged KMS helper to the NixOS configuration.

## Try this branch

Stop any recording first and start with a clean Git checkout. Unstow before
switching so the custom plugin's links are removed while its files still exist.

```bash
cd /etc/nixos
stow --dir="$PWD/dotfiles" --target="$HOME" --no-folding --delete niri noctalia
git switch panel-b
stow --dir="$PWD/dotfiles" --target="$HOME" --no-folding --restow niri noctalia
sudo nixos-rebuild switch --flake /etc/nixos#j2
noctalia msg plugins disable saleh/screen-recording-status
noctalia msg plugins enable noctalia/screen_recorder
noctalia msg config-reload
niri validate
```

The rebuild installs `gpu-screen-recorder`. The plugin commands install/enable
the official plugin and update Noctalia's saved selection, which otherwise
overrides the branch's enabled-plugin list. Allow enabling to finish; check:

```bash
noctalia msg plugins list | rg 'screen_recorder'
command -v gpu-screen-recorder
systemctl --user is-active xdg-desktop-portal xdg-desktop-portal-gnome
noctalia config validate
```

Record each display through the picker, change focus during capture, then stop
and play the saved video. Also cancel a picker and verify the indicator returns
to idle. Repeat at another desk without adding monitor mappings. This widget
tracks `gpu-screen-recorder`; it does not indicate recordings made with
`wf-recorder` or every other recording application.

If a recording fails, inspect
`~/.local/state/noctalia/screen_recorder/gpu-screen-recorder.log`.

Return to panel-a using its documented unstow/switch/restow sequence and rebuild
to restore `wf-recorder` if needed.

## Validation

Niri and Noctalia configuration validation passed against the installed official
plugin manifest. Nix evaluation confirms the desktop includes
`gpu-screen-recorder`. In an isolated Noctalia instance, the stock widget/service
loaded, found the native recorder, and accepted service IPC. Actual portal
selection and video capture remain part of the interactive branch trial.

## References

- [Official Noctalia recorder and IPC commands](https://docs.noctalia.dev/noctalia/plugins/official-plugins/#screen-recorder)
- [Upstream widget](https://github.com/noctalia-dev/official-plugins/blob/main/screen_recorder/recorder.luau)
- [Upstream settings](https://github.com/noctalia-dev/official-plugins/blob/main/screen_recorder/plugin.toml)
