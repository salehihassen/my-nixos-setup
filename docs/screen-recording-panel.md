# Screen recording, capture targets, and camera activity

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

Noctalia's built-in `privacy` widget also displays red microphone, camera, and
screen-sharing icons for active PipeWire captures; hovering lists the consuming
applications. Idle icons are hidden, so only confirmed activity is shown.
This uses the stock widget, with no additional plugin for privacy icons.

Chromium currently opens the Brio camera directly through V4L2, bypassing
PipeWire's camera links. A small fallback in the existing companion uses the
already-installed `lsof` to show `Camera on` in red while a process has a
camera capture endpoint open. Its tooltip identifies the device and process.
It does not open the camera, restart the browser, or alter the call. Memory
mappings and PipeWire/WirePlumber device ownership are excluded; the native
privacy widget handles actual PipeWire capture. This fallback indicates an
open camera descriptor, rather than inspecting frames or what a site transmits.

## Panel labels

- Red `REC middle` identifies a GPU Screen Recorder capture.
- Amber `SHARE #154` identifies a browser capture, including
  Google Meet sharing an application window through Niri.
- `REC+SHARE` indicates recording and browser sharing. Hover distinguishes
  consumers attached to one source from separate capture sessions.
- Amber `CAST` shows an active target when the consuming application is unknown
  or does not match the recorder/browser identities. It never guesses `REC`
  just because a recorder is running elsewhere.
- `PAUSED #55` shows a retained browser session with its selected target
  when Niri reports it is not streaming frames. Chromium's explicit PipeWire
  `node.target` identifies its consumer even before stream links are negotiated.
  This does not prove that the remote meeting is receiving frames.
- `Idle` means no active stream or identifiable paused consumer
  was found. Other inactive sessions are counted in the tooltip.
- `Capture ?` means the query failed; it does not claim that
  capture has stopped.
- `Camera on` indicates direct camera use. Combined states use `CAM+SHARE`,
  `CAM+REC`, or `CAM+PAUSED`; target details are available on hover.

The companion text is capped at 12 Unicode characters, leaving room for an
adjacent icon and a space while keeping the combined indicator under 15.
It has no additional icon of its own. Multiple captures use a compact state
and count; the tooltip lists all targets, titles, IDs, and consuming apps.

Monitor tooltips include the connector ID. The built-in eDP display is `built-in`;
the Acer KB272 and Dell P2717H are `middle` and `right`. External aliases match
manufacturer/model/serial identity, so connector renumbering does not change
their aliases. An unfamiliar monitor uses its connector in the bar and its
model plus connector in the tooltip, or just the connector when metadata is missing. The alias mapping
is at the top of
`dotfiles/noctalia/.local/share/noctalia/plugins/capture-target/status.mjs`.

Window labels show their Niri window ID; hover for full titles, consumer
applications, and cast IDs. Missing
window metadata retains the ID and explicitly reports an unavailable title.

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
These widgets need no Niri restart or NixOS rebuild. They use the
already-installed Node.js, Niri, PipeWire tools, and `lsof`.

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
long titles, multiple captures, and direct camera descriptors versus mappings
or PipeWire device ownership. For a live check, toggle the camera in Meet and
verify the `CAM` label appears/disappears, then select each monitor and a
window through the recorder picker; change focus and verify the target remains
correct. Stop and verify the label returns to idle. Repeat with a browser share
and with concurrent recording/sharing.

If a recording fails, inspect
`~/.local/state/noctalia/screen_recorder/gpu-screen-recorder.log`.

## References

- [Official Noctalia recorder](https://docs.noctalia.dev/noctalia/plugins/official-plugins/#screen-recorder)
- [Niri cast status](https://niri-wm.github.io/niri/niri_ipc/struct.Cast.html)
- [Niri capture targets](https://niri-wm.github.io/niri/niri_ipc/enum.CastTarget.html)
