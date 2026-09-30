# Niri desktop control

This j2-only service gives Codex and Pi the same monitor screenshots and
approved mouse/keyboard actions. It runs in the logged-in Wayland session.

## Activate

From `/etc/nixos`:

```sh
sudo nixos-rebuild switch --flake .#j2
systemctl --user start desktop-control.service
```

Codex's global MCP entry is installed with:

```sh
codex mcp add desktop-control -- /etc/profiles/per-user/saleh/bin/node /etc/nixos/scripts/desktop-control/mcp.mjs
```

Start a **new** Codex session to discover its tools. The Home Manager switch
links the Pi extension into `~/.pi/agent/extensions/`; restart Pi to load it.
If Pi's Kimi K3 model is still marked text-only, run
`node /etc/nixos/scripts/desktop-control/enable-pi-kimi-vision.mjs` after
confirming that your proxy route accepts images.

## Stop and restart

Either `Mod+BackSpace` or `Mod+Shift+BackSpace` stops the service, including
any pending approval dialog, and releases held virtual input. All desktop
tool calls then fail until you explicitly run:

```sh
systemctl --user start desktop-control.service
```

Check state with `systemctl --user status desktop-control.service`. The stop
shortcut also shows a Noctalia notification.

## First test

1. Ask Codex to list displays and screenshot the display containing KCalc.
2. Ask it to calculate `7 × 8` using KCalc's GUI and verify `56` in a new
   screenshot. Each input action should show a fuzzel `APPROVE`/`DENY` prompt.
3. Trigger either stop shortcut while an approval is pending. Verify that the
   action does not run and another tool call reports the service is stopped.
4. Restart the service, then repeat with Pi's Kimi K3 model. Its proxy route
   accepted a synthetic 256×256 image in the setup test, and the local Pi
   model declaration has been updated to advertise image input.

The stop shortcut controls this tool service. A coding harness with an
unrestricted same-user shell can still call `ydotool` itself, so run desktop
tasks with shell access restricted if the stop shortcut must be an enforced
boundary. Do not enable autonomous input until that is in place.
