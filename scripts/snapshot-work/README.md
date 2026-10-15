# Capture laptop work before ending a session

`capture-work` is ordinary local automation: it uses no generative AI, model,
API key, or inference endpoint. Niri supplies the window list and screenshots;
the script follows a fixed traversal and switches Chromium tabs with keyboard
commands. The optional `--cdp` endpoint is a local browser debugger, not an AI
service. Browser pages may still make their normal network requests when
selected. Fixed control flow does not guarantee complete live tab coverage:
the default tab counts come from saved browser sessions, as explained below.

## Home Manager installation

Import `home/snapshot-work.nix` independently of `home/desktop.nix`. The module
installs `capture-work` in the profile and at `~/.local/bin/capture-work`.

```nix
{
  imports = [ ./home/snapshot-work.nix ]; # Adjust relative to your HM file.
}
```

Flake consumers can instead import `inputs.<repo>.homeModules.snapshot-work`.
Importing the module installs the command; there is no separate `.enable`
option. Omit the import on systems that do not want it. Apply the change with
your usual Home Manager activation or NixOS rebuild. Removing the module
removes its managed launcher on activation; saved capture folders remain.
The module works with NixOS-integrated or standalone Home Manager on Linux,
but desktop screenshots require a running Niri Wayland session. It does not
configure a compositor or browser, and does not require the desktop module,
Noctalia, its capture indicator, or an AI agent.

`programs.snapshot-work.sourceMode = "store"` is the reusable default;
it packages the scripts in the Nix store and needs no `dotfilesRoot` argument.
`"checkout"` reads these files from `dotfilesRoot/scripts/snapshot-work` on every
invocation (j2's choice). Only the launcher/dependency changes need a switch in
checkout mode. Git tracks live script edits; Home Manager rollback does not.
Checkout mode requires an absolute `dotfilesRoot` passed through
`extraSpecialArgs` (or `home-manager.extraSpecialArgs` on NixOS).

## Host setup for browser tab switching

The launcher supplies Node.js, Niri CLI, grim, wl-clipboard and the ydotool
client. Home Manager does not install or configure the privileged `ydotoold`
daemon. For default keyboard tab capture, the host must provide either:

- A working `capture-keys` helper on `PATH`, supporting `tab-next` and
  `tab-prev`. On j2, `modules/desktop-control.nix` with
  `services.desktop-control.enable = true` supplies the daemon and a restricted
  setgid helper that can only send those two tab-switching chords. The
  interactive `desktop-control.service`, MCP server, approval UI and inference
  endpoint do not need to be running for `capture-work`.
- A running `ydotoold` daemon whose socket the desktop user can access. For a
  NixOS host using direct ydotool access, the system configuration can use:

  ```nix
  {
    programs.ydotool.enable = true;
    users.users.alice.extraGroups = [ "ydotool" ]; # Use your desktop username.
  }
  ```

  Rebuild and log out/in for new group membership. This grants general
  ydotool input access; j2 uses the restricted helper instead. For a custom
  socket, set `home.sessionVariables.YDOTOOL_SOCKET` to its path; the wrapper
  uses that value unless the caller already set the environment variable.
  Setting a path does not grant access to the socket. On non-NixOS hosts,
  configure the daemon and device/socket permissions through the host OS.

`--no-tabs` and `--backup-only` need no input-injection helper. An already
enabled `--cdp` browser debugger also bypasses keyboard tab switching. Per-tab
capture supports Chrome/Chromium; other applications, including other browser
families, receive ordinary window screenshots only. The default profile roots
are `~/.config/chromium`, `~/.config/google-chrome`, and
`~/.config/google-chrome-beta`. For another profile location, pass its user-data
root with `--browser-root` (repeatable), not its `Default` subdirectory.

## Running a capture

Run as your desktop user from a normal terminal or SSH session:

```sh
~/.local/bin/capture-work
```

This creates a new private folder under `~/Pictures/snapshot-work/`, named
with the capture's start time in UTC (for example `2026-10-04T14-51-09.659Z`).
The folder timestamp and manifest `startedAt` come from the same timestamp.
Open `index.html`
for the gallery, `manifest.json` for results/errors, and
`browser-inventory.json` for saved browser window/tab titles and URLs.
The gallery also lists window titles and column/row positions per workspace,
even when the lock screen prevented screenshots. Browser URLs are clickable.
Every run gets its own directory. Existing capture directories are never overwritten.

For manual installation, use Node.js 22 or newer, Niri supporting both
`screenshot-window --id --path` and `overview-state`, grim, wl-clipboard, and
the tab-input setup above. Run in an unlocked desktop with overview closed,
as the same user who owns the Niri session and browser profile; leave input
idle until completion. The script does not install, start, restart or
reconfigure any service or browser.

## Niri traversal

The script enumerates outputs, workspaces and windows. It visits every window
in column/row order within each workspace, across all monitors. Focusing a
window makes Niri scroll its column into view; simply screenshotting each
workspace once would miss off-screen columns. It saves a full window image
and a screenshot of the monitor after each focus change. Empty workspaces are
captured too. It does not wheel-scroll inside documents or terminal buffers.

At completion or interruption it attempts to restore each workspace's active
window, each monitor's active workspace, and the original global focus.
Niri's public actions do not restore arbitrary manual horizontal scroll offsets
exactly. During capture, leave the keyboard/mouse alone. Ctrl+C stops after
the current operation and preserves partial results.

Niri's built-in window screenshots also set the clipboard. The script backs up
one clipboard representation (preferably text, otherwise PNG) and restores it.
The raw backup is kept as `original-clipboard.bin` plus MIME metadata. Multiple
clipboard formats and clipboard history cannot be restored exactly.
If the clipboard was initially empty, it is cleared again after capture.

## Chromium tabs

The default works with an already open Chromium, without changing launch flags:

1. Copy each profile's saved `Sessions/Session_*` and `Tabs_*` files before
   taking screenshots. This includes historical files for recovery. The browser
   is still running, so these copies are not an atomic browser snapshot.
2. Parse the newest Session file into a best-effort tab inventory, with selected
   tabs and navigation URLs. Encrypted/unknown formats are backed up but not parsed.
3. Uniquely match each Niri Chromium window's active title against all saved tabs
   in each browser window, tolerating a stale saved selected-tab index. Use that
   window's saved tab count to capture the current tab, advance
   with Ctrl+Tab, and repeat. Reverse the issued advances with Ctrl+Shift+Tab
   afterward to return to the original tab.

Every browser tab gets at least **five seconds** to settle before its screenshot,
including the first tab. This also applies to CDP screenshots. For slow pages,
increase the wait with `--tab-delay 10000`. A fixed wait cannot guarantee that
every network request or lazy-loaded element has finished.

This fallback is explicitly **best effort**: saved state can lag, two browser
windows can have the same active title, a site can change its title, tab groups
can affect navigation, and discarded tabs can reload when selected. The report
never labels this as verified complete browser coverage. Ambiguous windows
are skipped with an error. For a known count, override the estimate:

```sh
niri msg --json windows
~/.local/bin/capture-work --tab-count 42:17 --tab-count 81:9
```

The numbers before `:` are **Niri window IDs**, not Chromium session IDs.
The script only switches tabs; it never types into page fields, navigates an
address bar, closes tabs, or reloads a page explicitly. A title observed at
capture time accompanies each image. Duplicate titles are not used as a
stop condition, since distinct tabs often share titles.

For exact browser target enumeration, use an **already enabled** local Chrome
DevTools Protocol endpoint:

```sh
~/.local/bin/capture-work --cdp http://127.0.0.1:9222
```

This captures each page target directly, without changing tabs or reloading.
It also saves main-document visible text and common form/contenteditable
values, excluding password, hidden and file inputs. Cross-origin frames,
canvas editors and application-internal buffers may not be represented.
Screenshots use the existing viewport; they are not full-page exports.
The endpoint must belong to the browser containing your work. The script
does not launch a replacement browser to obtain debugging access.

## Locked desktops, SSH and recovery limits

The script discovers a single Niri socket automatically when needed. For
multiple sessions, set `NIRI_SOCKET` and `WAYLAND_DISPLAY` explicitly.
It must run outside an agent sandbox that blocks desktop sockets.

Screen locks can prevent screenshots and focus changes. The script first
requires Niri overview to be closed; an open overview stops desktop capture
before screenshots, focus changes or browser input. It then
checks that Niri actually writes a window PNG; if that fails, it stops desktop
capture before keyboard input and retains the session backup and failure report.
It never unlocks, kills or restarts the locker, compositor or browser. CDP
capture, if an endpoint already exists, is independent of compositor capture.

```sh
~/.local/bin/capture-work --backup-only
~/.local/bin/capture-work --no-tabs
~/.local/bin/capture-work --delay 1500
~/.local/bin/capture-work --tab-delay 10000
~/.local/bin/capture-work --browser-root ~/.config/chromium
```

**Do not treat screenshots as saved work.** They preserve visible pixels,
not unsaved editor buffers, hidden terminal scrollback, off-screen document
content or all browser drafts. Chromium session files can help restore tabs
but are not a guarantee that unsaved text survives. Incognito tabs are not in
the disk inventory. This script never initiates a reboot.

Exit code 0 means the requested operations finished (the gallery may still
say `review-required` for best-effort coverage). Exit 2 means partial failure;
exit 1 is a setup/argument error. Always inspect the gallery and manifest
before ending the desktop session.

## Verification

```sh
# From the repository root:
node --test scripts/snapshot-work/capture.test.mjs
nix build 'path:.#checks.x86_64-linux.snapshot-wrappers' --no-link
```

Tests cover multi-monitor/workspace traversal, off-screen column ordering,
restoration after failure/interruption, lock-screen refusal before input,
ambiguous Chromium windows, truncated SNSS records, navigation history and
HTML escaping and empty-clipboard restoration. On October 4, 2026, the live
desktop test captured three windows, eight distinct Chromium tabs, and four
workspace views on the laptop display; original window focus and browser tab
were restored. Automated tests also cover multiple monitors.

On October 15, 2026, the live three-display test saved all 12 window images,
19 distinct browser-tab images across four Chromium windows, and 15 workspace
views, with no failures. Before/after queries confirmed original window focus,
active workspaces, workspace active windows, and browser tab titles were restored.
Every saved PNG passed structural checks. The gallery and `verification.json`
are in `~/Pictures/snapshot-work/2026-10-15T18-12-29.869Z/`. Browser counts still
come from saved sessions and remain best effort. Overview-open refusal is now
covered by an automated regression test.

Protocol references:

- [Niri actions](https://niri-wm.github.io/niri/niri_ipc/enum.Action.html)
- [Chromium session command IDs](https://github.com/chromium/chromium/blob/main/components/sessions/core/session_service_commands.cc)
- [Chromium record encoding](https://github.com/chromium/chromium/blob/main/components/sessions/core/session_command.cc)
- [Chromium navigation encoding](https://github.com/chromium/chromium/blob/main/components/sessions/core/serialized_navigation_entry.cc)
- [CDP screenshots](https://chromedevtools.github.io/devtools-protocol/tot/Page/#method-captureScreenshot)
- [CDP targets](https://chromedevtools.github.io/devtools-protocol/tot/Target/#method-getTargets)
