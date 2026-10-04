# Screen recording and capture targets

Noctalia's official `noctalia/screen_recorder` plugin owns recording, the
monitor/window picker, and the recorder icon. Super+Alt+R toggles recording;
starting opens the desktop portal picker, and stopping finalizes the video.
Videos go to `~/Videos/recording-YYYY-MM-DD_HH-MM-SS.mp4`, without audio.
The official plugin remains unmodified.

The local `saleh/capture-target` plugin adds a read-only label beside that icon.
Its singleton service polls Niri once per second and shares the result with
every bar instance. It reads the actual cast target, rather than the currently
focused monitor or window. PipeWire source-to-consumer links identify which
application is consuming each capture.

## Panel labels

- Red `REC · middle (DVI-I-2)` identifies a GPU Screen Recorder capture.
- Amber `SHARE · window: ~/ai (#154)` identifies a browser capture, including
  Google Meet sharing an application window through Niri.
- `REC+SHARE` means both consumers are attached to the same capture source.
- Amber `CAST` shows an active target when the consuming application is unknown
  or does not match the recorder/browser identities. It never guesses `REC`
  just because a recorder is running elsewhere.
- `No active capture` means Niri reports no actively streaming cast. Paused
  sessions are counted in the tooltip, rather than shown as active captures.
- `Capture status unavailable` means the query failed; it does not claim that
  capture has stopped.

Monitor labels include the connector ID. The built-in eDP display is `built-in`;
the Acer KB272 and Dell P2717H are `middle` and `right`. External aliases match
manufacturer/model/serial identity, so connector renumbering does not change
their aliases. An unfamiliar monitor uses its model and connector, such as
`Z27 (DP-3)`, or just the connector when metadata is missing. The alias mapping
is at the top of
`dotfiles/noctalia/.local/share/noctalia/plugins/capture-target/status.mjs`.

Window labels show their title and Niri window ID. Long titles are shortened in
the bar; hover for full titles, consumer applications, and cast IDs. Missing
window metadata retains the ID and explicitly reports an unavailable title.
The bar shows up to two active targets and a count of additional targets; the
tooltip lists all of them.

The label has no start/stop click action. Use the official recorder icon or
Super+Alt+R for recording controls and Google Meet's own controls for sharing.
Browser tab sharing that bypasses Niri is outside this label's scope. A browser
consumer is labeled `SHARE`; the label does not identify the particular site.

## Why portal capture

On this machine, `gpu-screen-recorder --info` lists the built-in display for
direct capture but does not list the two DisplayLink-connected displays. Portal
mode allows selecting those displays and unfamiliar office monitors through
Niri's desktop portal. It requires the existing `xdg-desktop-portal` and
`xdg-desktop-portal-gnome` services, with no additional privileged KMS helper.

## Apply changes

For an existing installation of the official recorder:

```bash
cd /etc/nixos
stow --dir="$PWD/dotfiles" --target="$HOME" --no-folding --restow noctalia
noctalia msg plugins enable saleh/capture-target
noctalia msg config-reload
noctalia config validate
```

Stow links the local plugin into `~/.local/share/noctalia/plugins/capture-target`
and refreshes the configuration links. Enabling updates Noctalia's saved plugin
selection, which otherwise overrides the configuration's enabled-plugin list.
This companion change needs no Niri restart or NixOS rebuild. It uses the
already-installed Node.js, Niri, and PipeWire tools.

For a fresh installation, also enable `noctalia/screen_recorder` and apply the
desktop NixOS configuration to install `gpu-screen-recorder`. The existing
Niri binding is in the Stow `niri` package.

## Validation

```bash
node --test scripts/capture-target.test.mjs
node dotfiles/noctalia/.local/share/noctalia/plugins/capture-target/status.mjs
noctalia plugins lint dotfiles/noctalia/.local/share/noctalia/plugins/capture-target
noctalia config validate
noctalia msg plugins list | rg 'capture-target|screen_recorder'
```

The tests cover simultaneous recorder/browser targets, physical monitor aliases
and unfamiliar monitors, paused casts, reused PipeWire IDs, missing metadata,
long titles, and multiple captures. For a live check, select each monitor and a
window through the recorder picker; change focus and verify the target remains
correct. Stop and verify the label returns to idle. Repeat with a browser share
and with concurrent recording/sharing.

If a recording fails, inspect
`~/.local/state/noctalia/screen_recorder/gpu-screen-recorder.log`.

## References

- [Official Noctalia recorder](https://docs.noctalia.dev/noctalia/plugins/official-plugins/#screen-recorder)
- [Niri cast status](https://niri-wm.github.io/niri/niri_ipc/struct.Cast.html)
- [Niri capture targets](https://niri-wm.github.io/niri/niri_ipc/enum.CastTarget.html)
