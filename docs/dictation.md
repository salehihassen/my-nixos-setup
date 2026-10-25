# Local dictation on J2

Voxtype 1.1.1 runs Whisper large-v3-turbo locally with Vulkan on J2's Radeon
680M. Optional polishing uses the local `llama3.2:3b` model through Ollama.
Nothing is enabled at login. No audio or transcripts are sent to a remote API.
Downloads are explicit; recordings and transcript files are temporary and
private under `$XDG_RUNTIME_DIR/dictation` and are removed after each request.

## Try it

- **Super+Alt+D** starts faithful dictation. Press again to finish.
- **Super+Alt+Shift+D** starts polished dictation. Press again to finish.
- Either shortcut finishes an active recording; its starting mode is retained.
- **Super+Alt+Escape** cancels recording, initialization, or processing.

Wait for **Listening** before speaking. **Preparing** includes loading the
models; **Processing** means the microphone is closed and inference is running.
Noctalia's existing privacy widget shows actual microphone capture. Recording
automatically ends after five minutes.

Text is inserted once through `wtype`, with line breaks replaced by spaces and
without submitting. If the original niri window is no longer focused, focus
cannot be verified, or typing fails, the result goes to the clipboard and a
notification appears. Switching fields within the same window is not detected.
Polishing failures, empty replies, and timeouts fall back to the faithful text.
The default polishing timeout is 45 seconds.

The CLI is also available at `~/.local/bin/dictation`:

```sh
~/.local/bin/dictation toggle faithful
~/.local/bin/dictation toggle polished
~/.local/bin/dictation cancel
~/.local/bin/dictation status
```

## Installation and activation

J2 enables `programs.dictation` in `home/j2.nix`. The reusable module is exported
as `homeModules.dictation`; other hosts do not import or enable it. Portable
configurations default to CPU Voxtype and CPU Ollama. J2 selects
`pkgs.voxtype-vulkan`. Package/model paths, download URL/checksum, microphone,
recording limit, idle timeout, polishing model/timeout/port, Ollama acceleration,
and optional niri integration can be overridden in the module's options.

For a normal system rebuild, the NixOS Home Manager integration activates it.
To activate the home generation directly without sudo, including untracked
implementation files:

```sh
nix build --out-link "$HOME/.local/state/dictation-home" \
  'path:/etc/nixos#nixosConfigurations.j2.config.home-manager.users.saleh.home.activationPackage'
"$HOME/.local/state/dictation-home/activate"
~/.local/bin/dictation setup
niri validate
```

`dictation setup` downloads and verifies the 1.62 GB Whisper GGML model and
pulls the roughly 2.02 GB Ollama cleanup model. Existing verified files are
reused. Model files live under `~/.local/share/voxtype/models` and
`~/.ollama/models`; they are outside Git and the Nix store. Setup stops its
Ollama service when finished. Subsequent dictation needs no network connection.

The optional `dictation.kdl` include in Stow's niri configuration receives
generated bindings from Home Manager; other hosts can omit that generated file.
No compositor restart or focus change is required.

## Service lifecycle

The controller socket and every dictation service/timer have no `WantedBy`
target. A shortcut starts the socket, which starts one event-driven Python
controller. Voxtype's inotify state events drive progress; there is no polling
monitor. A short, bounded HTTP readiness check is used only while Ollama starts.

Faithful mode starts only Voxtype. Polished mode also starts the Home Manager
user `ollama.service`, reserved by this module for dictation, on
**127.0.0.1:11435**. The default/system Ollama server on port 11434 is separate.
The dictation server uses the user's model files, disables cloud support, and
does not download models during a recording.

Each component gets a 60-second systemd idle timer after its processing
finishes. A new request stops the relevant timer before starting work. Idle
callbacks recheck whether the component is busy, so an already queued timer
cannot unload an active model. Ollama is explicitly unloaded before its service
stops. Stopping Voxtype releases Whisper and its GPU resources. The controller
exits once both components are released; the dormant socket remains available
until logout/reboot. Cancellation immediately stops capture/inference and also
schedules cleanup. A controller shutdown stops its dependent services and timers.

## Troubleshooting and tests

```sh
systemctl --user status dictation voxtype ollama
journalctl --user -u dictation -u voxtype -u ollama -n 60
systemctl --user list-timers 'dictation-*'
python3 -B /etc/nixos/scripts/test_dictation.py
nix build 'path:/etc/nixos#checks.x86_64-linux.dictation-tests'
```

On NixOS, the `default` ALSA input routes through the configured PipeWire ALSA
support. A custom microphone must use an ALSA name, not a `pactl` source name.
The controller suppresses Voxtype transcript logging and transcript notifications.
Diagnostic messages and model initialization metadata can still enter the journal.

Validation performed during installation is recorded below. Live microphone,
typing, and application tests are left for the user's first test session.

- Whisper download verified against SHA-256
  `1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69`.
- Local Ollama model digest:
  `a80c4f17acd55265feec403c7aef86be0c25983ab279d83f3bcd3abbcb5b8b72`.
- A public 11-second JFK sample transcribed successfully in **8.09 seconds**
  including cold model initialization. Backend diagnostics confirmed Vulkan on
  `AMD Radeon Graphics (RADV REMBRANDT)`. This is not a warm dictation benchmark.
- Whisper daemon readiness took **1.78 seconds cold** and **0.018 seconds warm**
  without opening the microphone. These are readiness times, not transcription
  times. The Voxtype cgroup reported about 602 MB after initialization; that
  does not account for all Vulkan GPU allocations.
- The cleanup model loaded on CPU in **5.92 seconds** and polished a synthetic
  sentence in **2.41 seconds**, preserving NixOS and removing filler words.
- Actual idle timers released Whisper after **61.24 seconds** and stopped the
  cleanup server after **62.21 seconds**, including timer accuracy/startup and
  shutdown overhead. All three services were inactive afterward, with no failed
  user units. The systemd control socket survived controller exit/restart.
- J2's home generation builds, niri configuration validates, standalone CPU
  configuration evaluates, and B1 remains unaffected.
- **18 regression tests passed**, including in a Nix build. They cover mode selection, cleanup failure/timeout, silence,
  cancellation, focus fallback, timer races, and real inotify state events.

Upstream interface reference: the pinned Voxtype source's
[`docs/CONFIGURATION.md`](https://github.com/peteonrails/voxtype/blob/v1.1.1/docs/CONFIGURATION.md).
