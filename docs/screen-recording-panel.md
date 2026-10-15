# Screen recording, capture targets, and camera activity

Noctalia's official `noctalia/screen_recorder` plugin owns recording, the
monitor/window picker, and the recorder icon. Super+Alt+R toggles recording;
starting opens the desktop portal picker, and stopping finalizes the video.
Videos go to `~/Videos/Screencast/recording-YYYY-MM-DD_HH-MM-SS.mp4`, without audio.
The official plugin remains unmodified.

The local `saleh/capture-target` plugin adds a read-only label beside that icon.
Its singleton service starts one persistent `capture-target-monitor` and shares
its JSON status stream with every bar instance. The monitor subscribes directly
to Niri's socket event stream and keeps one `pw-dump --monitor` connection for
PipeWire source-to-consumer links. It reads the actual cast target, rather than
the currently focused monitor or window. It publishes only changed status;
there are no periodic Niri queries, Node launches, or `lsof` scans.

Niri and PipeWire disconnects trigger bounded reconnect backoff, with unavailable
information reported explicitly. Noctalia owns the monitor process group and
terminates it when the service reloads or the plugin is disabled. A small shell
supervisor restarts the monitor after an unexpected exit, with a five-second
delay and an unavailable status between attempts.

Noctalia's built-in `privacy` widget also displays red microphone, camera, and
screen-sharing icons for active PipeWire captures; hovering lists the consuming
applications. Idle icons are hidden, so only confirmed activity is shown.
This uses the stock widget, with no additional plugin for privacy icons.

Chromium currently opens the Brio camera directly through V4L2, bypassing
PipeWire's camera links. The companion keeps one `inotifywait` watcher on camera
capture endpoints, plus a directory watcher for hotplug. It inspects readable
`/proc/*/fd` symlinks once after watches are established and after open/close
events, coalescing event bursts. There is no periodic descriptor scan. It shows
`Camera on` in red while a visible process has a capture endpoint open; its
tooltip identifies the device and process. Processes hidden from the desktop
user by kernel permissions cannot be attributed.
It does not open the camera, restart the browser, or alter the call. Memory
mappings and PipeWire/WirePlumber device ownership are excluded; the native
privacy widget handles actual PipeWire capture. This fallback indicates an
open camera descriptor, rather than inspecting frames or what a site transmits.
Watcher failures show `Camera ?` and retry with backoff; they do not claim that
the camera is inactive.

## On-demand work snapshots

`capture-work` is independent of this monitor. It captures windows across Niri
workspaces and outputs and traverses Chromium tabs only when invoked, then
exits. It writes a private gallery under `~/Pictures/snapshot-work/`. The monitor
does not take screenshots, cycle tabs, or open cameras. Keeping the status label
running is not necessary for work snapshots.

Browser inventory uses saved Chromium session data and remains best effort.
Matching now checks all saved tab titles in a window, tolerating a stale selected
index while still refusing ambiguous matches. Use explicit `--tab-count` values
or an already enabled CDP endpoint when saved state cannot identify coverage.
See [snapshot documentation](../scripts/snapshot-work/README.md).

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
# Install the monitor wrapper and its declared runtime dependencies initially.
nixos-rebuild switch --flake .#j2
stow --dir="$PWD/dotfiles" --target="$HOME" --no-folding --restow noctalia
noctalia msg plugins disable saleh/capture-target
noctalia msg plugins enable saleh/capture-target
noctalia config validate
```

Stow links the local plugin into `~/.local/share/noctalia/plugins/capture-target`
and refreshes the configuration links. Enabling updates Noctalia's saved plugin
selection, which otherwise overrides the configuration's enabled-plugin list.
After the wrapper is installed, edits to the monitor need only the Stow refresh
and companion-plugin disable/enable commands above. These do not restart Niri,
the browser, or the official recorder. `home/noctalia.nix` supplies the wrapper's
pinned Node.js, PipeWire, and inotify-tools dependencies; the script remains
editable in the checkout, matching the repository's existing Stow workflow.

For a fresh installation, also enable `noctalia/screen_recorder` and apply the
desktop NixOS configuration to install `gpu-screen-recorder`. The existing
Niri binding is in the Stow `niri` package.

## Validation

```bash
node --test scripts/capture-target.test.mjs
# inotifywait must be on PATH for the camera/stream integration tests.
node --test scripts/capture-target-monitor.test.mjs
node --test scripts/snapshot-work/capture.test.mjs
timeout 3 ~/.local/bin/capture-target-monitor
noctalia plugins lint dotfiles/noctalia/.local/share/noctalia/plugins/capture-target
noctalia config validate
noctalia msg plugins list | rg 'capture-target|screen_recorder'
```

The tests cover simultaneous recorder/browser targets, physical monitor aliases
and unfamiliar monitors, paused casts, reused PipeWire IDs, missing metadata,
long titles, multiple captures, and direct camera descriptors versus mappings
or PipeWire device ownership. Monitor integration tests use a temporary fake
Niri socket, PipeWire JSON batches, and ordinary temporary files as camera
endpoints; they cover open/close, hotplug, idle silence, reconnects, and cleanup
without opening a real camera or changing desktop focus. The flake's
`capture-target-tests` check supplies the integration-test dependencies.

For a live check, toggle the camera in Meet and
verify the `CAM` label appears/disappears, then select each monitor and a
window through the recorder picker; change focus and verify the target remains
correct. Stop and verify the label returns to idle. Repeat with a browser share
and with concurrent recording/sharing.

A real `capture-work` end-to-end test changes window focus and browser tabs.
Arrange a pause with the user before running it, then inspect the manifest and
confirm that the original focus and selected tabs were restored.

### October 15, 2026 efficiency verification

In a 15-second observation before replacement, the Noctalia scope used about
55.7% of one CPU core. In a 20-second observation afterward it used about 3.9%;
the persistent Node monitor itself used about 0.15% and retained the same PID.
These are short observations during normal desktop use, not controlled battery
watt measurements. The native privacy widget and official recorder remained
enabled.

The approved desktop snapshot test saved 46 screenshots: all 12 windows,
19 distinct browser-tab images across four Chromium windows, and 15 workspace
views across three displays, with zero failures or errors. Independent
before/after queries confirmed the original focused window, each output's
active workspace, each workspace's active window, and all four browsers'
original tab titles were restored. Every saved PNG passed structural checks.
Results and verification are in
`~/Pictures/snapshot-work/2026-10-15T18-12-29.869Z/`.
The report remains `review-required` because saved-session tab counts are
estimates, rather than verified enumeration of live browser tabs.

An earlier attempt ran while Niri overview was open and refused browser input
because no application had keyboard focus. The script now explicitly checks
overview and stops before screenshots or focus changes with instructions to
close it. All 31 automated tests and the updated Nix snapshot check passed.

If a recording fails, inspect
`~/.local/state/noctalia/screen_recorder/gpu-screen-recorder.log`.

## References

- [Official Noctalia recorder](https://docs.noctalia.dev/noctalia/plugins/official-plugins/#screen-recorder)
- [Niri cast status](https://niri-wm.github.io/niri/niri_ipc/struct.Cast.html)
- [Niri capture targets](https://niri-wm.github.io/niri/niri_ipc/enum.CastTarget.html)
