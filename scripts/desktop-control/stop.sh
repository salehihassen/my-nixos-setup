#!/usr/bin/env bash
# Stop the approved AI desktop-control service.
# NixOS hosts run it as a system service (passwordless via polkit);
# standalone Home Manager setups may still use the user unit.
if ! systemctl stop desktop-control.service 2>/dev/null; then
  systemctl --user stop desktop-control.service
fi
# A stop during a drag or chord must not leave the virtual device held down.
# On NixOS the system unit releases held buttons/keys via ExecStopPost; the
# ydotool calls below only help on standalone setups where the user can still
# reach the socket directly.
if command -v ydotool >/dev/null 2>&1; then
  ydotool click 0x80 0x81 0x82 >/dev/null 2>&1 || true
  ydotool key 29:0 42:0 56:0 125:0 >/dev/null 2>&1 || true
fi
# Deliberately no auto-restart: the next AI action should ask you to arm it again.
if command -v notify-send >/dev/null 2>&1; then
  notify-send "AI desktop control stopped" "Restart explicitly: systemctl start desktop-control.service"
fi
