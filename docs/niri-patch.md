# Niri popup redraw experiment

The `niri-patch` branch backports upstream commit
`0add05dde70df3c6d70362913aa007fac4c31f91` onto Niri 26.04 for `j2`.
The host overlay covers both the NixOS session package and Home Manager's Niri.
The patch is vendored unchanged in `patches/niri-popup-redraw.patch`.

Upstream references:

- Report: https://github.com/niri-wm/niri/issues/4216
- Fix: https://github.com/niri-wm/niri/commit/0add05dde70df3c6d70362913aa007fac4c31f91

The fix schedules redraws when a popup's child surface changes. Upstream
confirmed it for Firefox extension popups; whether it fixes the observed
Chromium/Bitwarden freezes still needs testing.

## Try it

From this checkout on the `niri-patch` branch:

```bash
sudo nixos-rebuild boot --flake .#j2
```

Reboot when ready. Using `boot` stages the new generation without switching the
current desktop session. After reboot, `niri --version` should include
`Nixpkgs+popup-redraw-0add05d`.

Use Chromium and Bitwarden normally and check whether popup typing, caret
blinking, and other updates continue while the pointer is stationary. If a
freeze returns, note whether moving the pointer or resizing the browser revives
it, and whether other extension popups are affected.

To return to the previous configuration, select the previous NixOS generation
at boot. For subsequent rebuilds, switch back to `main`.

Remove the overlay and vendored patch once the packaged Niri release includes
the upstream fix.
